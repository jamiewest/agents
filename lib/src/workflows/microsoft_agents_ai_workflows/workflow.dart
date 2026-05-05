import 'package:extensions/system.dart';

import 'checkpointing/edge_info.dart';
import 'checkpointing/representation_extensions.dart';
import 'checkpointing/request_port_info.dart';
import 'edge.dart';
import 'execution/external_request_sink.dart';
import 'executor_binding.dart';
import 'external_request.dart';
import 'external_request_context.dart';
import 'observability/workflow_telemetry_context.dart';
import 'protocol_descriptor.dart';
import 'request_port.dart';

/// A class that represents a workflow that can be executed.
class Workflow {
  /// Creates a [Workflow] with the given [startExecutorId].
  Workflow(
    this.startExecutorId, {
    this.name,
    this.description,
    WorkflowTelemetryContext? telemetryContext,
  }) : telemetryContext =
           telemetryContext ?? WorkflowTelemetryContext.disabled;

  /// A dictionary of executor providers, keyed by executor ID.
  Map<String, ExecutorBinding> executorBindings = {};

  Map<String, Set<Edge>> edges = {};

  Set<String> outputExecutors = {};

  Map<String, RequestPort> ports = {};

  /// Gets the identifier of the starting executor of the workflow.
  final String startExecutorId;

  /// Gets the optional human-readable name of the workflow.
  String? name;

  /// Gets the optional description of what the workflow does.
  String? description;

  /// Gets the telemetry context for the workflow.
  final WorkflowTelemetryContext telemetryContext;

  bool _needsReset = false;

  Object? _ownerToken;

  bool _ownedAsSubworkflow = false;

  /// Gets the collection of edges grouped by their source node identifier.
  Map<String, Set<EdgeInfo>> reflectEdges() {
    return Map.fromEntries(
      edges.entries.map(
        (e) => MapEntry(
          e.key,
          e.value.map((edge) => edge.toEdgeInfo()).toSet(),
        ),
      ),
    );
  }

  /// Gets the collection of external request ports, keyed by their ID.
  Map<String, RequestPortInfo> reflectPorts() {
    return Map.fromEntries(
      ports.entries.map(
        (e) => MapEntry(e.key, e.value.toPortInfo()),
      ),
    );
  }

  /// Gets a copy of the executor bindings dictionary.
  Map<String, ExecutorBinding> reflectExecutors() {
    return Map.of(executorBindings);
  }

  bool get allowConcurrent {
    return executorBindings.values.every(
      (r) => r.supportsConcurrentSharedExecution,
    );
  }

  Iterable<String> get nonConcurrentExecutorIds {
    return executorBindings.values
        .where((r) => !r.supportsConcurrentSharedExecution)
        .map((r) => r.id);
  }

  bool get hasResettableExecutors {
    return executorBindings.values.any((r) => r.supportsResetting);
  }

  Future<bool> tryResetExecutorRegistrations() async {
    if (hasResettableExecutors) {
      for (final registration in executorBindings.values) {
        if (!await registration.tryReset()) {
          return false;
        }
      }
      _needsReset = false;
      return true;
    }
    return false;
  }

  void checkOwnership({Object? existingOwnershipSignoff}) {
    final maybeOwned = _ownerToken;
    if (!identical(maybeOwned, existingOwnershipSignoff)) {
      throw StateError(
        'Existing ownership does not match check value. '
        '${_summarize(maybeOwned)} vs. ${_summarize(existingOwnershipSignoff)}',
      );
    }
  }

  void takeOwnership(
    Object ownerToken, {
    bool? subworkflow,
    Object? existingOwnershipSignoff,
  }) {
    final maybeToken = _compareExchange(ownerToken, existingOwnershipSignoff);
    if (maybeToken == null && existingOwnershipSignoff != null) {
      throw StateError(
        'Existing ownership token was provided, but the workflow is unowned.',
      );
    }
    if (maybeToken == null && _needsReset) {
      throw StateError(
        'Cannot reuse Workflow with shared Executor instances that do not '
        'implement ResettableExecutor.',
      );
    }
    if (!identical(maybeToken, existingOwnershipSignoff) &&
        !identical(maybeToken, ownerToken)) {
      final isSubworkflow = subworkflow ?? false;
      final message = switch ((isSubworkflow, _ownedAsSubworkflow)) {
        (true, true) =>
          'Cannot use a Workflow as a subworkflow of multiple parent workflows.',
        (true, false) =>
          'Cannot use a running Workflow as a subworkflow.',
        (false, true) =>
          'Cannot directly run a Workflow that is a subworkflow of another workflow.',
        (false, false) =>
          'Cannot use a Workflow that is already owned by another runner or parent workflow.',
      };
      throw StateError(message);
    }
    _needsReset = hasResettableExecutors;
    _ownedAsSubworkflow = subworkflow ?? false;
  }

  Future<void> releaseOwnership(
    Object ownerToken,
    Object? targetOwnerToken,
  ) async {
    final originalToken = _compareExchange(targetOwnerToken, ownerToken);
    if (originalToken == null) {
      throw StateError(
        'Attempting to release ownership of a Workflow that is not owned.',
      );
    }
    if (!identical(originalToken, ownerToken)) {
      throw StateError(
        'Attempt to release ownership of a Workflow by non-owner.',
      );
    }
    await tryResetExecutorRegistrations();
  }

  /// Retrieves a [ProtocolDescriptor] defining how to interact with this
  /// workflow.
  Future<ProtocolDescriptor> describeProtocol({
    CancellationToken? cancellationToken,
  }) async {
    final startBinding = executorBindings[startExecutorId]!;
    final startExecutor = await startBinding.createInstance('');
    startExecutor.attachRequestContext(NoOpExternalRequestContext());
    final inputProtocol = startExecutor.describeProtocol();
    final outputExecutorFutures = outputExecutors
        .map((id) => executorBindings[id]!.createInstance(''));
    final outputExecutorList = await Future.wait(outputExecutorFutures);
    // ignore: avoid_dynamic_calls
    final yieldedTypes = outputExecutorList
        .expand<Type>((e) => (e as dynamic)?.describeProtocol()?.yields ?? <Type>[]);
    return ProtocolDescriptor(
      inputProtocol.accepts,
      yieldedTypes,
      const [],
      inputProtocol.acceptsAll,
    );
  }

  /// In Dart (single event loop), compare-and-swap is a simple conditional
  /// assignment. Returns the original value of [_ownerToken].
  Object? _compareExchange(Object? newValue, Object? comparand) {
    final original = _ownerToken;
    if (identical(original, comparand)) {
      _ownerToken = newValue;
    }
    return original;
  }

  static String _summarize(Object? maybeOwnerToken) => switch (maybeOwnerToken) {
    final String s => "'$s'",
    null => '<null>',(_) => '${maybeOwnerToken.runtimeType}@${maybeOwnerToken.hashCode}',
  };
}

class NoOpExternalRequestContext
    implements ExternalRequestContext, ExternalRequestSink {
  NoOpExternalRequestContext();

  @override
  Future<void> post(ExternalRequest request) async {}

  @override
  ExternalRequestSink registerPort(RequestPort port) => this;
}

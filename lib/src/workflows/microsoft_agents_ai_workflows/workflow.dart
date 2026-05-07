import 'edge.dart';
import 'executor_binding.dart';
import 'protocol_descriptor.dart';
import 'request_port.dart';

/// A class that represents a workflow that can be executed.
class Workflow {
  /// Creates a [Workflow] with the given [startExecutorId].
  Workflow(
    this.startExecutorId, {
    this.name,
    this.description,
    Iterable<ExecutorBinding> executorBindings = const <ExecutorBinding>[],
    Iterable<Edge> edges = const <Edge>[],
    Iterable<String> outputExecutorIds = const <String>[],
    Iterable<RequestPortDescriptor> requestPorts =
        const <RequestPortDescriptor>[],
  }) : _executorBindings = Map<String, ExecutorBinding>.unmodifiable({
         for (final binding in executorBindings) binding.id: binding,
       }),
       _edges = List<Edge>.unmodifiable(edges),
       _outputExecutorIds = List<String>.unmodifiable(outputExecutorIds),
       _requestPorts = List<RequestPortDescriptor>.unmodifiable(requestPorts);

  /// Gets the identifier of the starting executor of the workflow.
  final String startExecutorId;

  /// Gets the optional human-readable name of the workflow.
  String? name;

  /// Gets the optional description of what the workflow does.
  String? description;

  final Map<String, ExecutorBinding> _executorBindings;
  final List<Edge> _edges;
  final List<String> _outputExecutorIds;
  final List<RequestPortDescriptor> _requestPorts;

  Object? _ownerToken;
  bool _ownedAsSubworkflow = false;
  bool _needsReset = false;

  /// Gets whether the workflow can run concurrently.
  bool get allowConcurrent => nonConcurrentExecutorIds.isEmpty;

  /// Gets IDs for any executors that do not support concurrent execution.
  Iterable<String> get nonConcurrentExecutorIds => _executorBindings.values
      .where(
        (binding) =>
            binding.isSharedInstance &&
            !binding.supportsConcurrentSharedExecution,
      )
      .map((binding) => binding.id);

  /// Gets whether any bound executors support resetting.
  bool get hasResettableExecutors =>
      _executorBindings.values.any((binding) => binding.supportsResetting);

  /// Gets the executor bindings registered with the workflow.
  Iterable<ExecutorBinding> reflectExecutors() => _executorBindings.values;

  /// Gets the edges registered with the workflow.
  Iterable<Edge> reflectEdges() => _edges;

  /// Gets output executor identifiers.
  Iterable<String> reflectOutputExecutors() => _outputExecutorIds;

  /// Gets request ports exposed by the workflow.
  Iterable<RequestPortDescriptor> reflectPorts() => _requestPorts;

  /// Describes the workflow protocol from the start executor and outputs.
  Future<ProtocolDescriptor> describeProtocol() async {
    final acceptedTypes = <Type>[];
    var acceptsAll = false;
    final startBinding = _executorBindings[startExecutorId];
    if (startBinding != null) {
      final startProtocol = await startBinding.describeProtocol();
      acceptedTypes.addAll(startProtocol.acceptedTypes);
      acceptsAll = startProtocol.acceptsAll;
    }

    final producedTypes = <Type>[];
    final seenPorts = <RequestPortDescriptor>{..._requestPorts};
    for (final outputExecutorId in _outputExecutorIds) {
      final binding = _executorBindings[outputExecutorId];
      if (binding == null) {
        continue;
      }
      final protocol = await binding.describeProtocol();
      for (final producedType in protocol.producedTypes) {
        if (!producedTypes.contains(producedType)) {
          producedTypes.add(producedType);
        }
      }
      seenPorts.addAll(protocol.requestPorts);
    }

    return ProtocolDescriptor(
      acceptedTypes: acceptedTypes,
      producedTypes: producedTypes,
      requestPorts: seenPorts,
      acceptsAll: acceptsAll,
    );
  }

  /// Attempts to reset executor registrations.
  Future<bool> tryResetExecutorRegistrations() async {
    if (_needsReset && !hasResettableExecutors) {
      return false;
    }
    var resetAny = false;
    for (final binding in _executorBindings.values) {
      if (!binding.supportsResetting) {
        continue;
      }
      final reset = await binding.tryReset();
      resetAny = resetAny || reset;
      if (!reset) {
        return false;
      }
    }
    _needsReset = false;
    return resetAny;
  }

  /// Verifies current ownership.
  void checkOwnership({Object? existingOwnershipSignoff}) {
    final maybeOwned = _ownerToken;
    if (!identical(maybeOwned, existingOwnershipSignoff)) {
      throw StateError(
        'Existing ownership does not match check value. '
        '${_summarize(maybeOwned)} vs. ${_summarize(existingOwnershipSignoff)}',
      );
    }
  }

  /// Takes ownership of this workflow for a run or parent workflow.
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
        (true, false) => 'Cannot use a running Workflow as a subworkflow.',
        (false, true) =>
          'Cannot directly run a Workflow that is a subworkflow of another workflow.',
        (false, false) =>
          'Cannot use a Workflow that is already owned by another runner or parent workflow.',
      };
      throw StateError(message);
    }
    _needsReset = !allowConcurrent || hasResettableExecutors;
    _ownedAsSubworkflow = subworkflow ?? false;
  }

  /// Releases ownership of this workflow.
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
    if (targetOwnerToken == null) {
      _ownedAsSubworkflow = false;
    }
  }

  Object? _compareExchange(Object? newValue, Object? comparand) {
    final original = _ownerToken;
    if (identical(original, comparand)) {
      _ownerToken = newValue;
    }
    return original;
  }

  static String _summarize(Object? maybeOwnerToken) =>
      switch (maybeOwnerToken) {
        final String s => "'$s'",
        null => '<null>',
        _ => '${maybeOwnerToken.runtimeType}@${maybeOwnerToken.hashCode}',
      };
}

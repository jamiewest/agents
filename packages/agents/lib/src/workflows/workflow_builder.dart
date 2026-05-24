import 'direct_edge_data.dart';
import 'edge.dart';
import 'edge_id.dart';
import 'executor_binding.dart';
import 'fan_in_edge_data.dart';
import 'fan_out_edge_data.dart';
import 'request_port.dart';
import 'workflow.dart';

/// Builder for creating a [Workflow] from executor bindings and edges.
class WorkflowBuilder {
  /// Creates a workflow builder with a starting executor binding.
  WorkflowBuilder(ExecutorBinding startExecutor)
    : startExecutorId = startExecutor.id {
    addExecutor(startExecutor);
  }

  /// Gets the start executor identifier.
  final String startExecutorId;

  String? _name;
  String? _description;
  var _nextEdgeId = 0;
  final Map<String, ExecutorBinding> _executorBindings =
      <String, ExecutorBinding>{};
  final List<Edge> _edges = <Edge>[];
  final List<String> _outputExecutorIds = <String>[];
  final List<RequestPortDescriptor> _requestPorts = <RequestPortDescriptor>[];

  /// Sets the workflow name.
  WorkflowBuilder withName(String? name) {
    _name = name;
    return this;
  }

  /// Sets the workflow description.
  WorkflowBuilder withDescription(String? description) {
    _description = description;
    return this;
  }

  /// Adds or replaces an executor binding.
  WorkflowBuilder addExecutor(ExecutorBinding binding) {
    _executorBindings[binding.id] = binding;
    return this;
  }

  /// Adds an output executor identifier.
  WorkflowBuilder addOutput(String executorId) {
    _throwIfExecutorMissing(executorId);
    if (!_outputExecutorIds.contains(executorId)) {
      _outputExecutorIds.add(executorId);
    }
    return this;
  }

  /// Adds a workflow-level external request port.
  WorkflowBuilder addRequestPort(RequestPortDescriptor port) {
    if (!_requestPorts.contains(port)) {
      _requestPorts.add(port);
    }
    return this;
  }

  /// Adds a direct edge.
  WorkflowBuilder addEdge(
    String sourceExecutorId,
    String targetExecutorId, {
    Type? messageType,
  }) {
    _throwIfExecutorMissing(sourceExecutorId);
    _throwIfExecutorMissing(targetExecutorId);
    _edges.add(
      Edge(
        DirectEdgeData(
          id: _createEdgeId(),
          sourceExecutorId: sourceExecutorId,
          targetExecutorId: targetExecutorId,
          messageType: messageType,
        ),
      ),
    );
    return this;
  }

  /// Adds a fan-out edge.
  WorkflowBuilder addFanOutEdge(
    String sourceExecutorId,
    Iterable<String> targetExecutorIds,
  ) {
    _throwIfExecutorMissing(sourceExecutorId);
    final targets = List<String>.of(targetExecutorIds);
    for (final targetExecutorId in targets) {
      _throwIfExecutorMissing(targetExecutorId);
    }
    _edges.add(
      Edge(
        FanOutEdgeData(
          id: _createEdgeId(),
          sourceExecutorId: sourceExecutorId,
          targetExecutorIds: targets,
        ),
      ),
    );
    return this;
  }

  /// Adds a fan-in edge.
  WorkflowBuilder addFanInEdge(
    Iterable<String> sourceExecutorIds,
    String targetExecutorId,
  ) {
    final sources = List<String>.of(sourceExecutorIds);
    for (final sourceExecutorId in sources) {
      _throwIfExecutorMissing(sourceExecutorId);
    }
    _throwIfExecutorMissing(targetExecutorId);
    _edges.add(
      Edge(
        FanInEdgeData(
          id: _createEdgeId(),
          sourceExecutorIds: sources,
          targetExecutorId: targetExecutorId,
        ),
      ),
    );
    return this;
  }

  /// Builds the workflow.
  Workflow build() => Workflow(
    startExecutorId,
    name: _name,
    description: _description,
    executorBindings: _executorBindings.values,
    edges: _edges,
    outputExecutorIds: _outputExecutorIds,
    requestPorts: _requestPorts,
  );

  EdgeId _createEdgeId() => EdgeId('edge-${++_nextEdgeId}');

  void _throwIfExecutorMissing(String executorId) {
    if (!_executorBindings.containsKey(executorId)) {
      throw StateError('Executor "$executorId" is not registered.');
    }
  }
}

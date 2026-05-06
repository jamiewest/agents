import '../../func_typedefs.dart';
import '../microsoft_agents_ai_purview/models/common/activity.dart';
import 'direct_edge_data.dart';
import 'edge.dart';
import 'edge_id.dart';
import 'executor_binding.dart';
import 'executor_placeholder.dart';
import 'fan_in_edge_data.dart';
import 'fan_out_edge_data.dart';
import 'observability/event_names.dart';
import 'observability/tags.dart';
import 'observability/workflow_telemetry_context.dart';
import 'portable_value.dart';
import 'checkpointing/workflow_representation_extensions.dart';
import 'workflow.dart';
import 'workflows_json_utilities.dart';
import '../../json_stubs.dart';
import '../../activity_stubs.dart';

/// Provides a builder for constructing and configuring a workflow by defining
/// executors and the connections between them.
///
/// Remarks: Use the WorkflowBuilder to incrementally add executors and edges,
/// including fan-in and fan-patterns, before building a strongly-typed
/// workflow instance. Executors must be bound before building the workflow.
/// All executors must be bound by calling into [ExecutorBinding)] if they
/// were intially specified as [IsPlaceholder].
class WorkflowBuilder {
  /// Initializes a new instance of the WorkflowBuilder class with the specified
  /// starting executor.
  ///
  /// [start] The executor that defines the starting point of the workflow.
  /// Cannot be null.
  WorkflowBuilder(ExecutorBinding start) {
    this._startExecutorId = this.track(start).id;
  }

  int _edgeCount;

  final Map<String, ExecutorBinding> _executorBindings = {};

  final Map<String, Set<Edge>> _edges = {};

  final Set<String> _unboundExecutors = {};

  final Set<EdgeConnection> _conditionlessConnections = {};

  final Map<String, RequestPort> _requestPorts = {};

  final Set<String> _outputExecutors = {};

  late final String _startExecutorId;

  late String? _name;

  late String? _description;

  WorkflowTelemetryContext _telemetryContext = WorkflowTelemetryContext.disabled;

  ExecutorBinding track(ExecutorBinding binding) {
    if (binding.isPlaceholder && !this._executorBindings.containsKey(binding.id)) {
      // If this is an unbound executor, we need to track it separately
            this._unboundExecutors.add(binding.id);
    } else if (!binding.isPlaceholder) {
      ExecutorBinding existing;
      if (this._executorBindings.containsKey(binding.id)) {
        if (existing.executorType != binding.executorType) {
          throw StateError(
                        "Cannot bind executor with ID ${binding.id} because an executor with the same ID but a different type (${existing.executorType.name} vs ${binding.executorType.name}) is already bound.");
        }
        if (existing.rawValue != null &&
                    !identical(existing.rawValue, binding.rawValue)) {
          throw StateError(
                        "Cannot bind executor with ID ${binding.id} because an executor with the same ID but different instance is already bound.");
        }
      } else {
        this._executorBindings[binding.id] = binding;
        if (this._unboundExecutors.contains(binding.id)) {
          this._unboundExecutors.remove(binding.id);
        }
      }
    }
    if (binding is RequestPortBinding) {
      final portRegistration = binding as RequestPortBinding;
      var port = portRegistration.port;
      this._requestPorts[port.id] = port;
    }
    return binding;
  }

  /// Register executors as an output source. Executors can use
  /// [CancellationToken)] to yield output values. By default, message handlers
  /// with a non-void return type will also be yielded, unless
  /// [AutoYieldOutputHandlerResultObject] is set to `false`.
  ///
  /// Returns:
  ///
  /// [executors]
  WorkflowBuilder withOutputFrom(List<ExecutorBinding> executors) {
    for (final executor in executors) {
      this._outputExecutors.add(this.track(executor).id);
    }
    return this;
  }

  /// Sets the human-readable name for the workflow.
  ///
  /// Returns: The current [WorkflowBuilder] instance, enabling fluent
  /// configuration.
  ///
  /// [name] The name of the workflow.
  WorkflowBuilder withName(String name) {
    this._name = name;
    return this;
  }

  /// Sets the description for the workflow.
  ///
  /// Returns: The current [WorkflowBuilder] instance, enabling fluent
  /// configuration.
  ///
  /// [description] The description of what the workflow does.
  WorkflowBuilder withDescription(String description) {
    this._description = description;
    return this;
  }

  /// Sets the telemetry context for the workflow.
  ///
  /// [context] The telemetry context to use.
  void setTelemetryContext(WorkflowTelemetryContext context) {
    this._telemetryContext = context;
  }

  /// Binds the specified executor (via registration) to the workflow, allowing
  /// it to participate in workflow execution.
  ///
  /// Returns: The current [WorkflowBuilder] instance, enabling fluent
  /// configuration.
  ///
  /// [registration] The executor instance to bind. The executor must exist in
  /// the workflow and not be already bound.
  WorkflowBuilder bindExecutor(ExecutorBinding registration) {
    if (registration is ExecutorPlaceholder) {
      throw StateError(
                "Cannot bind executor with ID ${registration.id} because it is a placeholder registration. " +
                "You must provide a concrete executor instance or registration.");
    }
    this.track(registration);
    return this;
  }

  Set<Edge> ensureEdgesFor(String sourceId) {
    Set<Edge>? edges;
    if (!this._edges.containsKey(sourceId)) {
      this._edges[sourceId] = edges = [];
    }
    return edges;
  }

  /// Adds a directed edge from the specified source executor to the target
  /// executor, optionally guarded by a condition.
  ///
  /// Returns: The current instance of [WorkflowBuilder].
  ///
  /// [source] The executor that acts as the source node of the edge. Cannot be
  /// null.
  ///
  /// [target] The executor that acts as the target node of the edge. Cannot be
  /// null.
  ///
  /// [condition] An optional predicate that determines whether the edge should
  /// be followed based on the input. An optional label for the edge. Will be
  /// used in visualizations.
  ///
  /// [idempotent] If set to `true`, adding the same edge multiple times will be
  /// a NoOp, rather than an error.
  WorkflowBuilder addEdge<T>(
    ExecutorBinding source,
    ExecutorBinding target,
    {bool? idempotent, Func<T?, bool>? condition, String? label, }
  ) {
    // Add an edge from source to target with an optional condition.
        // This is a low-level builder method that does not enforce any specific executor type.
        // The condition can be used to determine if the edge should be followed based on the input.
    var connection = new(source.id, target.id);
    if (condition == null && this._conditionlessConnections.contains(connection)) {
      if (idempotent) {
        return this;
      }
      throw StateError(
                'An edge from ${source.id} to "${target.id}" already exists without a condition. ' +
                "You cannot add another edge without a condition for the same source and target.");
    }
    var directEdge = new(
      this.track(source).id,
      this.track(target).id,
      this.takeEdgeId(),
      createConditionFunc(condition),
      label,
    );
    this.ensureEdgesFor(source.id).add(new(directEdge));
    return this;
  }

  static Func<Object?, bool>? createConditionFunc<T>({Func<T?, bool>? condition}) {
    if (condition == null) {
      return null;
    }
    return (maybeObj) {
        
            if (T != Object && maybeObj is PortableValue PortableValue)
            {
                maybeObj = PortableValue.asType(T);
      }
            return condition(maybeObj is T ? typed : default);
        };
  }

  EdgeId takeEdgeId() {
    return new((++this._edgeCount));
  }

  /// Adds a fan-from the specified source executor to one or more
  /// target executors, optionally using a custom partitioning function.
  ///
  /// Remarks: If a partitioner function is provided, it will be used to
  /// distribute input across the target executors. The order of targets
  /// determines their mapping in the partitioning process.
  ///
  /// Returns: The current instance of [WorkflowBuilder].
  ///
  /// [source] The source executor from which the fan-originates.
  /// Cannot be null.
  ///
  /// [targets] One or more target executors that will receive the fan-edge.
  /// Cannot be null or empty.
  ///
  /// [targetSelector] An optional function that determines how input is
  /// assigned among the target executors. If null, messages will route to all
  /// targets.
  ///
  /// [label] An optional label for the edge. Will be used in visualizations.
  WorkflowBuilder addFanOutEdge<T>(
    ExecutorBinding source,
    Iterable<ExecutorBinding> targets,
    {String? label, Func2<T?, int, Iterable<int>>? targetSelector, }
  ) {
    var sinkIds = targets.map((target) {
        
            target;
            return this.track(target).id;
        }).toList();
    sinkIds;
    var fanOutEdge = new(
            this.track(source).id,
            sinkIds,
            this.takeEdgeId(),
            createTargetAssignerFunc(targetSelector),
            label);
    this.ensureEdgesFor(source.id).add(new(fanOutEdge));
    return this;
  }

  static Func2<Object?, int, Iterable<int>>? createTargetAssignerFunc<T>(Func2<T?, int, Iterable<int>>? targetAssigner) {
    if (targetAssigner == null) {
      return null;
    }
    return (maybeObj, count) {
        
            if (T != Object && maybeObj is PortableValue PortableValue)
            {
                maybeObj = PortableValue.asType(T);
      }

            return targetAssigner(maybeObj is T ? typed : default, count);
        };
  }

  /// Adds a fan-in "barrier" edge to the workflow, connecting multiple source
  /// executors to a single target executor. Messages will be held until every
  /// source executor has generated at least one message, then they will be
  /// streamed to the target executor in the following step.
  ///
  /// Returns: The current instance of [WorkflowBuilder].
  ///
  /// [sources] One or more source executors that provide input to the target.
  /// Cannot be null or empty.
  ///
  /// [target] The target executor that receives input from the specified source
  /// executors. Cannot be null.
  WorkflowBuilder addFanInBarrierEdge(
    Iterable<ExecutorBinding> sources,
    ExecutorBinding target,
    {String? label, }
  ) {
    return this.addFanInBarrierEdge(sources, target, label: null);
  }

  void validate(bool validateOrphans) {
    if (this._unboundExecutors.length > 0) {
      throw StateError(
                'Workflow cannot be built because there are unbound executors: ${this._unboundExecutors.join(", ")}.');
    }
    var remainingExecutors = [...this._executorBindings.keys];
    var toVisit = new([this._startExecutorId]);
    if (!validateOrphans) {
      return;
    }
    while (toVisit.length > 0) {
      var currentId = toVisit.dequeue();
      var unvisited = remainingExecutors.remove(currentId);
      Set<Edge>? outgoingEdges;
      if (unvisited &&
                this._edges.containsKey(currentId)) {
        for (final edge in outgoingEdges) {
          switch (edge.data) {
            case DirectEdgeData directEdgeData:
            toVisit.enqueue(directEdgeData.sinkId);
            case FanOutEdgeData fanOutEdgeData:
            for (final targetId in fanOutEdgeData.sinkIds) {
              toVisit.enqueue(targetId);
            }
            case FanInEdgeData fanInEdgeData:
            toVisit.enqueue(fanInEdgeData.sinkId);
          }
        }
      }
    }
    if (remainingExecutors.length > 0) {
      throw StateError(
                'Workflow cannot be built because there are unreachable executors: ${remainingExecutors.join(", ")}.');
    }
  }

  Workflow buildInternal(bool validateOrphans, {Activity? activity, }) {
    activity?.addEvent(activityEvent(EventNames.buildStarted));
    try {
      this.validate(validateOrphans);
    } catch (e, s) {
      if (e is Exception) {
        final ex = e as Exception;
        {
          activity.addEvent(activityEvent(EventNames.buildError, tags: new(),
                { Tags.buildErrorType, ex.runtimeType.fullName }
            }));
        activity.captureException(ex);
        rethrow;
      }
    } else {
      rethrow;
    }
  }

  activity?.addEvent(activityEvent(EventNames.buildValidationCompleted));
  var workflow = workflow(
    this._startExecutorId,
    this._name,
    this._description,
    this._telemetryContext,
  );
  // Using the start executor ID as a proxy for the workflow ID
        activity?.setTag(Tags.workflowId, workflow.startExecutorId);
  if (workflow.name != null) {
    activity?.setTag(Tags.workflowName, workflow.name);
  }

  if (workflow.description != null) {
    activity?.setTag(Tags.workflowDescription, workflow.description);
  }

  activity?.setTag(
                Tags.workflowDefinition,
                JsonSerializer.serialize(
                    workflow.toWorkflowInfo(),
                    WorkflowsJsonUtilities.jsonContext.defaultValue.workflowInfo
                )
            );
  return workflow;
}
/// Builds and returns a workflow instance.
///
/// [validateOrphans] Specifies whether workflow validation should check for
/// Executor nodes that are not reachable from the starting executor.
Workflow build({bool? validateOrphans}) {
var activity = this._telemetryContext.startWorkflowBuildActivity();
var workflow = this.buildInternal(validateOrphans, activity);
activity?.addEvent(activityEvent(EventNames.buildCompleted));
return workflow;
 }
 }
class EdgeConnection extends ValueType {
  const EdgeConnection(
    String SourceId,
    String TargetId,
  ) :
      sourceId = SourceId,
      targetId = TargetId;

  String sourceId;

  String targetId;

  @override
  String toString() {
    return '${this.sourceId} -> ${this.targetId}';
  }

  @override
  bool operator ==(Object other) { if (identical(this, other)) return true;
    return other is EdgeConnection &&
    sourceId == other.sourceId &&
    targetId == other.targetId; }
  @override
  int get hashCode { return Object.hash(sourceId, targetId); }
}

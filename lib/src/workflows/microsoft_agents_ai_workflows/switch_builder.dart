import '../../func_typedefs.dart';
import 'executor_binding.dart';
import 'workflow_builder.dart';

/// Provides a builder for constructing a switch-like control flow that maps
/// predicates to one or more executors. Enables the configuration of
/// case-based and default execution logic for dynamic input handling.
class SwitchBuilder {
  SwitchBuilder();

  final List<ExecutorBinding> _executors = [];

  final Map<String, int> _executorIndicies = {};

  final List<FuncobjectboolPredicate, HashSetintOutgoingIndicies> _caseMap = [];

  final Set<int> _defaultIndicies = {};

  /// Adds a case to the switch builder that associates a predicate with one or
  /// more executors.
  ///
  /// Remarks: Cases are evaluated in the order they are added.
  ///
  /// Returns: The current [SwitchBuilder] instance, allowing for method
  /// chaining.
  ///
  /// [predicate] A function that determines whether the associated executors
  /// should be considered for execution. The function receives an input Object
  /// and returns `true` to select the case; otherwise, `false`.
  ///
  /// [executors] One or more executors to associate with the predicate. Each
  /// executor will be invoked if the predicate matches. Cannot be null.
  SwitchBuilder addCase<T>(
    Func<T?, bool> predicate,
    Iterable<ExecutorBinding> executors,
  ) {
    var indicies = [];
    for (final executor in executors) {
      int index;
      if (!this._executorIndicies.containsKey(executor.id)) {
        index = this._executors.length;
        this._executors.add(executor);
        this._executorIndicies[executor.id] = index;
      }
      indicies.add(index);
    }
    var casePredicate = WorkflowBuilder.createConditionFunc(predicate)!;
    this._caseMap.add((casePredicate, indicies));
    return this;
  }

  /// Adds one or more executors to be used as the default case when no other
  /// predicates match.
  ///
  /// Returns:
  ///
  /// [executors]
  SwitchBuilder withDefault(Iterable<ExecutorBinding> executors) {
    for (final executor in executors) {
      int index;
      if (!this._executorIndicies.containsKey(executor.id)) {
        index = this._executors.length;
        this._executors.add(executor);
        this._executorIndicies[executor.id] = index;
      }
      this._defaultIndicies.add(index);
    }
    return this;
  }

  WorkflowBuilder reduceToFanOut(
    WorkflowBuilder builder,
    ExecutorBinding source,
  ) {
    var caseMap = this._caseMap;
    var defaultIndicies = this._defaultIndicies;
    return builder.addFanOutEdge<Object>(source, this._executors, EdgeSelector);
    /* TODO: unsupported node kind "unknown" */
    // Iterable<int> EdgeSelector(Object? input, int targetCount)
    //         {
    //             Debug.Assert(targetCount == this._executors.Count);
    //
    //             for (int i = 0; i < caseMap.Count; i++)
    //             {
    //                 (Func<Object?, bool> predicate, Set<int> outgoingIndicies) = caseMap[i];
    //                 if (predicate(input))
    //                 {
    //                     return outgoingIndicies;
    //                 }
    //             }
    //
    //             return defaultIndicies;
    //         }
  }
}

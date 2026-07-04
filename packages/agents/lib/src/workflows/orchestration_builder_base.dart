import 'dart:collection';

import '../abstractions/ai_agent.dart';
import 'output_tag.dart';
import 'workflow_builder.dart';

/// Common fluent surface shared by every orchestration-style workflow
/// builder: human-readable name + description, and the [withOutputFrom] /
/// [withIntermediateOutputFrom] output-designation pair with memoized
/// defaults-suppression semantics.
///
/// [TBuilder] is the concrete builder type, for fluent self-return.
abstract class OrchestrationBuilderBase<
  TBuilder extends OrchestrationBuilderBase<TBuilder>
> {
  String? _name;
  String? _description;

  /// Memoized output designations, keyed by agent identity (agent id).
  ///
  /// `null` means the user has not made any explicit designation, and the
  /// orchestration-specific defaults will be applied at `build()` time. A
  /// non-null (possibly empty) map means the user took control and only
  /// these designations will be replayed onto the inner [WorkflowBuilder].
  /// An entry's value is the set of tags requested for the agent — an empty
  /// set encodes a terminal-only designation.
  LinkedHashMap<AIAgent, Set<OutputTag>>? _outputDesignations;

  TBuilder get _self => this as TBuilder;

  /// Sets the human-readable name for the workflow.
  TBuilder withName(String name) {
    _name = name;
    return _self;
  }

  /// Sets the description for the workflow.
  TBuilder withDescription(String description) {
    _description = description;
    return _self;
  }

  /// Designates the given [agents] as sources of terminal workflow output.
  ///
  /// Calling any output-designation method (this or
  /// [withIntermediateOutputFrom]) suppresses the orchestration-specific
  /// defaults: only the user-specified designations reach the inner
  /// [WorkflowBuilder].
  TBuilder withOutputFrom(Iterable<AIAgent> agents) {
    final designations = _ensureDesignations();
    for (final agent in agents) {
      designations.putIfAbsent(agent, () => <OutputTag>{});
    }
    return _self;
  }

  /// Designates the given [agents] as sources of *intermediate* workflow
  /// output. See [withOutputFrom] for the defaults-suppression semantics.
  TBuilder withIntermediateOutputFrom(Iterable<AIAgent> agents) {
    final designations = _ensureDesignations();
    for (final agent in agents) {
      designations
          .putIfAbsent(agent, () => <OutputTag>{})
          .add(OutputTag.intermediate);
    }
    return _self;
  }

  /// Applies the optional name and description to [builder]. Intended for
  /// subclasses, which should call this from their `build()` implementation.
  void applyMetadata(WorkflowBuilder builder) {
    final name = _name;
    if (name != null && name.trim().isNotEmpty) {
      builder.withName(name);
    }
    final description = _description;
    if (description != null && description.trim().isNotEmpty) {
      builder.withDescription(description);
    }
  }

  /// Applies the user's memoized output designations to [builder], or
  /// invokes [applyDefaults] if the user made no explicit designation.
  ///
  /// [agentExecutorIds] maps each participating agent (by [AIAgent.id]) to
  /// its bound executor id. [orchestrationKind] is used in the
  /// not-a-participant error message (e.g. "sequential", "concurrent").
  /// Intended for subclasses' `build()` implementations.
  void applyOutputDesignations(
    WorkflowBuilder builder,
    Map<String, String> agentExecutorIds,
    String orchestrationKind,
    void Function() applyDefaults,
  ) {
    final designations = _outputDesignations;
    if (designations == null) {
      applyDefaults();
      return;
    }

    for (final entry in designations.entries) {
      final agent = entry.key;
      final executorId = agentExecutorIds[agent.id];
      if (executorId == null) {
        throw StateError(
          'Output designation references agent '
          "'${agent.name ?? agent.id}', which is not a participant in this "
          '$orchestrationKind workflow.',
        );
      }

      final tags = entry.value;
      if (tags.isEmpty) {
        builder.withOutputFrom([executorId]);
      } else {
        for (final tag in tags) {
          builder.withOutputFrom([executorId], tag: tag);
        }
      }
    }
  }

  LinkedHashMap<AIAgent, Set<OutputTag>> _ensureDesignations() =>
      _outputDesignations ??= LinkedHashMap<AIAgent, Set<OutputTag>>(
        equals: (a, b) => a.id == b.id,
        hashCode: (agent) => agent.id.hashCode,
      );
}

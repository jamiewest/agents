import 'package:extensions/ai.dart';

/// Combines [UsageDetails] reported by the individual service or agent
/// invocations that make up a single logical run.
///
/// Several components re-invoke an inner agent or chat client in a loop
/// within a single run (for example when auto-approving tool calls, injecting
/// messages, or re-running an agent until an evaluator is satisfied). Each
/// inner invocation reports its own usage, and the aggregate must be surfaced
/// to the caller so that the reported token counts reflect the entire run
/// rather than just its final step.
abstract final class UsageAggregator {
  /// Combines two [UsageDetails] instances into a new instance containing
  /// their summed values.
  ///
  /// Neither argument is mutated, and neither argument is ever returned by
  /// reference, since both may be owned and observed by callers and
  /// [UsageDetails.add] combines in place. Every strongly-typed counter
  /// exposed by [UsageDetails] is summed, matching the set covered by
  /// [UsageDetails.add], so that no provider-reported counter is lost when a
  /// combined instance replaces the original. Token counts are summed in a
  /// null-aware manner: combining a `null` count with a non-null count yields
  /// the non-null count, and combining two `null` counts yields `null`.
  /// Entries in [UsageDetails.additionalCounts] are summed per key so that
  /// provider-specific counters (such as cached, reasoning, or cost counters)
  /// aggregate correctly. Returns `null` when both [current] and [incoming]
  /// are `null`.
  static UsageDetails? combine(UsageDetails? current, UsageDetails? incoming) {
    if (current == null && incoming == null) {
      return null;
    }

    return UsageDetails(
      inputTokenCount: _addCounts(
        current?.inputTokenCount,
        incoming?.inputTokenCount,
      ),
      outputTokenCount: _addCounts(
        current?.outputTokenCount,
        incoming?.outputTokenCount,
      ),
      totalTokenCount: _addCounts(
        current?.totalTokenCount,
        incoming?.totalTokenCount,
      ),
      cachedInputTokenCount: _addCounts(
        current?.cachedInputTokenCount,
        incoming?.cachedInputTokenCount,
      ),
      reasoningTokenCount: _addCounts(
        current?.reasoningTokenCount,
        incoming?.reasoningTokenCount,
      ),
      additionalCounts: _combineAdditionalCounts(
        current?.additionalCounts,
        incoming?.additionalCounts,
      ),
    );
  }

  /// Adds two nullable counts, treating `null` as "not reported" rather than
  /// as zero so that an aggregate only reports a count when at least one
  /// contributor reported one.
  static int? _addCounts(int? current, int? incoming) {
    if (current == null) return incoming;
    if (incoming == null) return current;
    return current + incoming;
  }

  /// Produces a new map containing the per-key sums of the supplied
  /// additional counts, or `null` when neither side has any entries.
  static Map<String, int>? _combineAdditionalCounts(
    Map<String, int>? current,
    Map<String, int>? incoming,
  ) {
    final hasCurrent = current != null && current.isNotEmpty;
    final hasIncoming = incoming != null && incoming.isNotEmpty;
    if (!hasCurrent && !hasIncoming) {
      return null;
    }

    final combined = <String, int>{};
    if (hasCurrent) {
      combined.addAll(current);
    }
    if (hasIncoming) {
      for (final entry in incoming.entries) {
        combined[entry.key] = (combined[entry.key] ?? 0) + entry.value;
      }
    }
    return combined;
  }
}

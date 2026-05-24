import '../../abstractions/ai_agent.dart';

/// Describes a handoff to a specific target [AIAgent].
class HandoffTarget {
  /// Creates a [HandoffTarget].
  const HandoffTarget(this.target, [this.reason]);

  /// Gets the target agent.
  final AIAgent target;

  /// Gets the reason for handing off to the target.
  final String? reason;

  @override
  bool operator ==(Object other) =>
      other is HandoffTarget && target.id == other.target.id;

  @override
  int get hashCode => target.id.hashCode;
}

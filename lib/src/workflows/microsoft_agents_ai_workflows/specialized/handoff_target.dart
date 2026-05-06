import 'package:extensions/ai.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
/// Describes a handoff to a specific target [AIAgent].
class HandoffTarget extends ValueType {
  /// Describes a handoff to a specific target [AIAgent].
  HandoffTarget(AIAgent Target, {String? Reason = null}) : target = Target;

  AIAgent target;

  String? reason;

  @override
  bool equals(HandoffTarget other) {
    return this.target.id == other.target.id;
  }

  @override
  int hashCode {
    return this.target.id.hashCode;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HandoffTarget &&
        target == other.target &&
        reason == other.reason;
  }

  @override
  int get hashCode {
    return Object.hash(target, reason);
  }
}

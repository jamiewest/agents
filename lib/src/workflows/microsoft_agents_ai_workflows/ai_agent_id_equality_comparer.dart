import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';

/// Compares [AIAgent] instances by their [AIAgent.id] property.
class AIAgentIdEqualityComparer {
  const AIAgentIdEqualityComparer._();

  /// A shared singleton instance.
  static const AIAgentIdEqualityComparer instance =
      AIAgentIdEqualityComparer._();

  /// Returns `true` if [x] and [y] have the same [AIAgent.id].
  bool equals(AIAgent? x, AIAgent? y) => x?.id == y?.id;

  /// Returns a hash code based on [obj]'s [AIAgent.id].
  int getHashCode(AIAgent obj) => obj.id.hashCode;
}

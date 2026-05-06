import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';

class AIAgentIDEqualityComparer {
  AIAgentIDEqualityComparer();

  static final AIAgentIDEqualityComparer instance = AIAgentIDEqualityComparer();

  bool equals(AIAgent? x, AIAgent? y) {
    return x?.id == y?.id;
  }

  int getHashCode(AIAgent obj) {
    return obj.id.hashCode;
  }
}

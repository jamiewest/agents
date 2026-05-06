import 'package:extensions/ai.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
class AIAgentIDEqualityComparer implements EqualityComparer<AIAgent> {
  AIAgentIDEqualityComparer();

  static final AIAgentIDEqualityComparer instance;

  @override
  bool equals(AIAgent? x, AIAgent? y) {
    return x?.id == y?.id;
  }

  @override
  int getHashCode(AIAgent obj) {
    return obj?.hashCode ?? 0;
  }
}

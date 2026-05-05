import 'package:extensions/ai.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
extension AIAgentExtensions on AIAgent {
  /// Derives from an agent a unique but also hopefully descriptive name that
  /// can be used as an executor's name or in a function name.
  String getDescriptiveId() {
    var id = (agent.name == null || agent.name.isEmpty)
        ? agent.id
        : '${agent.name}_${agent.id}';
    return invalidNameCharsRegex().replaceAll(id, "_");
  }
}

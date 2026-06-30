import 'package:agents/agents.dart';

import 'flutter_harness_agent_options.dart';

void applyFlutterHarnessPlatformDefaults(
  FlutterHarnessAgentOptions options, {
  required bool isWeb,
}) {
  if (!isWeb) {
    return;
  }

  if (!options.disableFileMemory && options.fileMemoryStore == null) {
    options.fileMemoryStore = InMemoryAgentFileStore();
  }
  if (!options.disableFileAccess && options.fileAccessStore == null) {
    options.fileAccessStore = InMemoryAgentFileStore();
  }
  if (!options.disableAgentSkillsProvider &&
      options.agentSkillsSource == null) {
    options.agentSkillsSource = AgentInMemorySkillsSource(const []);
  }
}

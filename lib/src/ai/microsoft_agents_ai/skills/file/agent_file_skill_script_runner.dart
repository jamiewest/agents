import 'package:extensions/dependency_injection.dart';
import 'package:extensions/system.dart';

import '../../../../json_stubs.dart';
import 'agent_file_skill.dart';
import 'agent_file_skill_script.dart';

/// Function for running file-based skill scripts.
typedef AgentFileSkillScriptRunner =
    Future<Object?> Function(
      AgentFileSkill skill,
      AgentFileSkillScript script,
      JsonElement? arguments,
      ServiceProvider? serviceProvider, {
      CancellationToken? cancellationToken,
    });

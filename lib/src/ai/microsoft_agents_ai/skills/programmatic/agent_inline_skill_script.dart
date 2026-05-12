import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:extensions/system.dart';

import '../../../../json_stubs.dart';
import '../agent_skill.dart';
import '../agent_skill_script.dart';

/// A skill script backed by a delegate.
class AgentInlineSkillScript extends AgentSkillScript {
  AgentInlineSkillScript(
    super.name,
    String? description,
    JsonSerializerOptions? serializerOptions, {
    Function? method,
  }) : _method = method,
       super(description: description);

  final Function? _method;

  @override
  JsonElement? get parametersSchema => const JsonElement({'type': 'object'});

  @override
  Future<Object?> run(
    AgentSkill skill,
    JsonElement? arguments,
    ServiceProvider? serviceProvider, {
    CancellationToken? cancellationToken,
  }) async {
    final method = _method;
    if (method == null) {
      return null;
    }

    final value = arguments?.value;
    final positional = value is List ? value : const [];
    final result = Function.apply(method, positional);
    return result is Future ? await result : result;
  }

  static AIFunctionArguments convertToFunctionArguments(
    JsonElement? arguments,
  ) {
    final value = arguments?.value;
    if (value == null) {
      return AIFunctionArguments();
    }
    if (value is! Map) {
      throw StateError(
        'Inline skill scripts expect arguments as a JSON Object.',
      );
    }
    return AIFunctionArguments(
      value.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}

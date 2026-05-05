import 'package:extensions/system.dart';
import 'package:extensions/dependency_injection.dart';
import '../agent_skill.dart';
import '../agent_skill_script.dart';
import '../../../../json_stubs.dart';

/// A skill script backed by a delegate.
class AgentInlineSkillScript extends AgentSkillScript {
  /// Initializes a new instance of the [AgentInlineSkillScript] class from a
  /// delegate. The delegate's parameters and return type are automatically
  /// marshaled via [AIFunctionFactory].
  ///
  /// [name] The script name.
  ///
  /// [method] A method to execute when the script is invoked. Parameters are
  /// automatically deserialized from JSON.
  ///
  /// [description] An optional description of the script.
  ///
  /// [serializerOptions] Optional [JsonSerializerOptions] used to marshal the
  /// delegate's parameters and return value. When `null`, [DefaultOptions] is
  /// used.
  AgentInlineSkillScript(
    String name,
    String? description,
    JsonSerializerOptions? serializerOptions,
    {Delegate? method = null, Object? target = null, },
  ) {
    var options = AIFunctionFactoryOptions();
    this._function = AIFunctionFactory.create(method, options);
  }

  late final AIFunction _function;

  /// Gets the JSON schema describing the parameters accepted by this script, or
  /// `null` if not available.
  JsonElement? get parametersSchema {
    return this._function.jsonSchema;
  }

  @override
  Future<Object?> run(
    AgentSkill skill,
    JsonElement? arguments,
    ServiceProvider? serviceProvider,
    {CancellationToken? cancellationToken, },
  ) async  {
    var funcArgs = convertToFunctionArguments(arguments);
    funcArgs.services = serviceProvider;
    return await this._function.invokeAsync(funcArgs, cancellationToken);
  }

  /// Converts a raw [JsonElement] to [AIFunctionArguments] for delegate
  /// invocation.
  static AIFunctionArguments convertToFunctionArguments(JsonElement? arguments) {
    if (arguments == null ||
            arguments.value.valueKind == JsonValueKind.nullValue ||
            arguments.value.valueKind == JsonValueKind.undefined) {
      return [];
    }
    if (arguments.value.valueKind != JsonValueKind.Object) {
      throw StateError(
                "Inline skill scripts expect arguments as a JSON Object but received a JSON element of kind ${arguments.value.valueKind}.");
    }
    var dict = new Dictionary<String, Object?>();
    for (final property in arguments.value.enumerateObject()) {
      dict[property.name] = property.value;
    }
    return aiFunctionArguments(dict);
  }
}

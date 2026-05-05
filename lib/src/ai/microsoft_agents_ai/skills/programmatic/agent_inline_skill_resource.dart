import 'package:extensions/system.dart';
import 'package:extensions/dependency_injection.dart';
import '../agent_skill_resource.dart';
import '../../../../json_stubs.dart';

/// A skill resource defined in code, backed by either a static value or a
/// delegate.
class AgentInlineSkillResource extends AgentSkillResource {
  /// Initializes a new instance of the [AgentInlineSkillResource] class with a
  /// static value. The value is returned as-is when [CancellationToken)] is
  /// called.
  ///
  /// [name] The resource name.
  ///
  /// [value] The static resource value.
  ///
  /// [description] An optional description of the resource.
  AgentInlineSkillResource(
    String name,
    String? description, {
    Object? value = null,
    Delegate? method = null,
    JsonSerializerOptions? serializerOptions = null,
    Object? target = null,
  }) {
    this._value = value;
  }

  late final Object? _value;

  final AIFunction? _function;

  @override
  Future<Object?> read({
    ServiceProvider? serviceProvider,
    CancellationToken? cancellationToken,
  }) async {
    if (this._function != null) {
      return await this._function
          .invokeAsync(aiFunctionArguments(), cancellationToken)
          ;
    }
    return this._value;
  }
}

import 'package:extensions/dependency_injection.dart';
import 'package:extensions/system.dart';

import '../../../../json_stubs.dart';
import '../agent_skill_resource.dart';

/// A skill resource defined in code, backed by either a static value or a
/// delegate.
class AgentInlineSkillResource extends AgentSkillResource {
  AgentInlineSkillResource(
    super.name,
    String? description, {
    Object? value,
    Future<Object?> Function({
      ServiceProvider? serviceProvider,
      CancellationToken? cancellationToken,
    })?
    callback,
    Function? method,
    JsonSerializerOptions? serializerOptions,
  }) : _value = value,
       _callback = callback,
       _method = method,
       super(description: description);

  final Object? _value;
  final Future<Object?> Function({
    ServiceProvider? serviceProvider,
    CancellationToken? cancellationToken,
  })?
  _callback;
  final Function? _method;

  @override
  Future<Object?> read({
    ServiceProvider? serviceProvider,
    CancellationToken? cancellationToken,
  }) async {
    final callback = _callback;
    if (callback != null) {
      return callback(
        serviceProvider: serviceProvider,
        cancellationToken: cancellationToken,
      );
    }
    final method = _method;
    if (method != null) {
      final result = Function.apply(method, const []);
      return result is Future ? await result : result;
    }
    return _value;
  }
}

/// A tool call that an agent is expected to make.
///
/// Remarks: Used with `EvaluateAsync` to assert that the agent called the
/// correct tools. The evaluator decides matching semantics (order, extras,
/// argument checking); this type is pure data.
///
/// [Name] The tool/function name (e.g. `"get_weather"`).
///
/// [Arguments] Expected arguments. `null` means "don't check arguments". When
/// provided, evaluators typically do subset matching (all expected keys must
/// be present).
class ExpectedToolCall {
  /// A tool call that an agent is expected to make.
  ///
  /// Remarks: Used with `EvaluateAsync` to assert that the agent called the
  /// correct tools. The evaluator decides matching semantics (order, extras,
  /// argument checking); this type is pure data.
  ///
  /// [Name] The tool/function name (e.g. `"get_weather"`).
  ///
  /// [Arguments] Expected arguments. `null` means "don't check arguments". When
  /// provided, evaluators typically do subset matching (all expected keys must
  /// be present).
  ExpectedToolCall(String Name, {Map<String, Object>? Arguments = null})
    : name = Name;

  /// The tool/function name (e.g. `"get_weather"`).
  String name;

  /// Expected arguments. `null` means "don't check arguments". When provided,
  /// evaluators typically do subset matching (all expected keys must be
  /// present).
  Map<String, Object>? arguments;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExpectedToolCall &&
        name == other.name &&
        arguments == other.arguments;
  }

  @override
  int get hashCode {
    return Object.hash(name, arguments);
  }
}

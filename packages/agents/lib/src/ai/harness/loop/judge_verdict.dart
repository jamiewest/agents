/// The structured verdict returned by the judge chat client used by an
/// AI-judge loop evaluator.
///
/// Internal to the loop evaluators (not exported from the package barrel);
/// mirrors the C# `internal sealed class JudgeVerdict`.
class JudgeVerdict {
  /// Creates a [JudgeVerdict].
  JudgeVerdict({this.answered = false, this.gapAnalysis = ''});

  /// Creates a [JudgeVerdict] from its JSON representation.
  factory JudgeVerdict.fromJson(Map<String, dynamic> json) => JudgeVerdict(
    answered: json['answered'] as bool? ?? false,
    gapAnalysis: json['gapAnalysis'] as String? ?? '',
  );

  /// Whether the agent has fully addressed the user's original request.
  bool answered;

  /// An explanation of what is still missing when the request has not been
  /// fully addressed.
  String gapAnalysis;
}

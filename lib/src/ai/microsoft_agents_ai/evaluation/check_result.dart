/// Result of a single check on a single evaluation item.
///
/// [Passed] Whether the check passed.
///
/// [Reason] Human-readable explanation.
///
/// [CheckName] Name of the check that produced this result.
class EvalCheckResult {
  /// Result of a single check on a single evaluation item.
  ///
  /// [Passed] Whether the check passed.
  ///
  /// [Reason] Human-readable explanation.
  ///
  /// [CheckName] Name of the check that produced this result.
  const EvalCheckResult(this.passed, this.reason, this.checkName);

  /// Whether the check passed.
  final bool passed;

  /// Human-readable explanation.
  final String reason;

  /// Name of the check that produced this result.
  final String checkName;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EvalCheckResult &&
        passed == other.passed &&
        reason == other.reason &&
        checkName == other.checkName;
  }

  @override
  int get hashCode {
    return Object.hash(passed, reason, checkName);
  }
}

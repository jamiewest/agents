/// A reference to a generated rubric evaluator that already exists in the
/// provider's registry.
///
/// Pass instances of this class to a batch evaluator to score items with a
/// pre-existing rubric evaluator that was authored in the provider's portal
/// or via the provider's dedicated SDK. Agent Framework is a consumer here:
/// it does not create or modify the evaluator definition; it only references
/// the persisted version by name.
///
/// Pinning [version] is strongly recommended so evaluation runs are
/// reproducible. A `null` [version] resolves to whichever version is current
/// at execution time; consuming evaluators are expected to emit a warning
/// when a versionless reference is used. CI gates should always pass a
/// concrete version.
class GeneratedEvaluatorRef {
  /// Creates a reference to the evaluator [name], optionally pinned to
  /// [version].
  const GeneratedEvaluatorRef(this.name, {this.version, this.displayName});

  /// Creates a versionless reference that resolves to the latest version of
  /// the evaluator at run time.
  ///
  /// Discouraged for reproducible runs. Prefer the primary constructor with
  /// an explicit [version] so CI and replay evaluations stay stable when the
  /// evaluator is updated in the provider's registry.
  static GeneratedEvaluatorRef latest(String name, {String? displayName}) =>
      GeneratedEvaluatorRef(name, displayName: displayName);

  /// Evaluator name as stored in the provider's registry (for example
  /// `"reservation-policy-rubric"`). Distinct from built-in evaluators such
  /// as `"relevance"`.
  final String name;

  /// Pinned evaluator version. `null` means "latest" — discouraged for
  /// reproducible runs; consumers may emit a warning when used.
  final String? version;

  /// Optional human-readable name used in result summaries. Defaults to
  /// [name] when unset.
  final String? displayName;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GeneratedEvaluatorRef &&
        name == other.name &&
        version == other.version &&
        displayName == other.displayName;
  }

  @override
  int get hashCode => Object.hash(name, version, displayName);
}

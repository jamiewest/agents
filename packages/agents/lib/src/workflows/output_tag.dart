/// Identifies the kind of output that a `WorkflowOutputEvent` represents.
///
/// A thin `ChatRole`-style wrapper around a normalized string [value], with
/// value equality and a closed set of well-known singletons (the constructor
/// is library-private for now, mirroring the upstream `internal` constructor).
final class OutputTag {
  const OutputTag._(this.value);

  /// The string identifier of the tag. Compared with ordinal equality.
  final String value;

  /// The tag denoting an intermediate workflow output — emitted by executors
  /// registered via `WorkflowBuilder.withIntermediateOutputFrom`. Terminal
  /// (non-intermediate) outputs carry no tag.
  static const OutputTag intermediate = OutputTag._('intermediate');

  /// Resolves [value] to a well-known singleton when possible; otherwise
  /// wraps it in a new tag. Used when reading persisted workflow state.
  static OutputTag fromValue(String value) =>
      value == intermediate.value ? intermediate : OutputTag._(value);

  @override
  bool operator ==(Object other) => other is OutputTag && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

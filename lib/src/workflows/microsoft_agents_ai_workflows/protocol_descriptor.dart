/// Describes the protocol for communication with a [Workflow] or [Executor].
class ProtocolDescriptor {
  ProtocolDescriptor(
    Iterable<Type> acceptedTypes,
    Iterable<Type> yieldedTypes,
    Iterable<Type> sentTypes,
    bool acceptsAll,
  )   : accepts = acceptedTypes.toList(),
        yields = yieldedTypes.toList(),
        sends = sentTypes.toList(),
        acceptsAll = acceptsAll;

  /// Get the collection of types explicitly accepted by the [Workflow] or
  /// [Executor].
  final List<Type> accepts;

  /// Gets the collection of types that could be yielded as output by the
  /// [Workflow] or [Executor].
  final List<Type> yields;

  /// Gets the collection of types that could be sent from the [Executor]. This
  /// is always empty for a [Workflow].
  final List<Type> sends;

  /// Gets a value indicating whether the [Workflow] or [Executor] has a
  /// "catch-all" handler.
  bool acceptsAll;
}

import 'request_port.dart';

/// Describes the message protocol supported by an executor or workflow.
class ProtocolDescriptor {
  /// Creates a protocol descriptor.
  ProtocolDescriptor({
    Iterable<Type> acceptedTypes = const <Type>[],
    Iterable<Type> producedTypes = const <Type>[],
    Iterable<RequestPortDescriptor> requestPorts =
        const <RequestPortDescriptor>[],
    this.acceptsAll = false,
  }) : acceptedTypes = List<Type>.unmodifiable(acceptedTypes),
       producedTypes = List<Type>.unmodifiable(producedTypes),
       requestPorts = List<RequestPortDescriptor>.unmodifiable(requestPorts);

  /// Gets the accepted input message types.
  final List<Type> acceptedTypes;

  /// Gets the produced output message types.
  final List<Type> producedTypes;

  /// Gets the external request ports exposed by the protocol.
  final List<RequestPortDescriptor> requestPorts;

  /// Gets whether all input message types are accepted.
  final bool acceptsAll;

  /// Gets whether [type] can be accepted by this protocol.
  bool accepts(Type type) => acceptsAll || acceptedTypes.contains(type);

  /// Gets whether [type] can be produced by this protocol.
  bool produces(Type type) => producedTypes.contains(type);

  /// Creates an empty protocol descriptor.
  static final ProtocolDescriptor empty = ProtocolDescriptor();
}

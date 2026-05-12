import 'protocol_descriptor.dart';
import 'request_port.dart';

/// Builder used by executors to describe their accepted and produced messages.
class ProtocolBuilder {
  final List<Type> _acceptedTypes = <Type>[];
  final List<Type> _producedTypes = <Type>[];
  final List<RequestPortDescriptor> _requestPorts = <RequestPortDescriptor>[];
  bool _acceptsAll = false;

  /// Marks this protocol as accepting messages of type [T].
  ProtocolBuilder acceptsMessage<T>() {
    _addUnique(_acceptedTypes, T);
    return this;
  }

  /// Marks this protocol as accepting messages of the given runtime [type].
  ProtocolBuilder acceptsMessageType(Type type) {
    _addUnique(_acceptedTypes, type);
    return this;
  }

  /// Marks this protocol as accepting every message type.
  ProtocolBuilder acceptsAllMessages() {
    _acceptsAll = true;
    return this;
  }

  /// Marks this protocol as producing messages of type [T].
  ProtocolBuilder sendsMessage<T>() {
    _addUnique(_producedTypes, T);
    return this;
  }

  /// Adds a request/response port to the protocol.
  ProtocolBuilder requests<TRequest, TResponse>(
    RequestPort<TRequest, TResponse> port,
  ) {
    final descriptor = port.toDescriptor();
    if (!_requestPorts.contains(descriptor)) {
      _requestPorts.add(descriptor);
    }
    return this;
  }

  /// Adds an existing request port descriptor to the protocol.
  ProtocolBuilder requestsDescriptor(RequestPortDescriptor port) {
    if (!_requestPorts.contains(port)) {
      _requestPorts.add(port);
    }
    return this;
  }

  /// Builds an immutable protocol descriptor.
  ProtocolDescriptor build() => ProtocolDescriptor(
    acceptedTypes: _acceptedTypes,
    producedTypes: _producedTypes,
    requestPorts: _requestPorts,
    acceptsAll: _acceptsAll,
  );

  static void _addUnique(List<Type> list, Type type) {
    if (!list.contains(type)) {
      list.add(type);
    }
  }
}

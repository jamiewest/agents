import 'identified.dart';

/// Describes an external request/response port available to an executor.
class RequestPort<TRequest, TResponse> implements Identified {
  /// Creates a request port with the supplied [id].
  const RequestPort(this.id, {this.description});

  /// Gets the port identifier.
  @override
  final String id;

  /// Gets an optional human-readable description for the port.
  final String? description;

  /// Gets the request payload type.
  Type get requestType => TRequest;

  /// Gets the response payload type.
  Type get responseType => TResponse;

  /// Creates a non-generic view of this port.
  RequestPortDescriptor toDescriptor() => RequestPortDescriptor(
    id,
    requestType: requestType,
    responseType: responseType,
    description: description,
  );

  @override
  String toString() => id;
}

/// Non-generic description for a [RequestPort].
class RequestPortDescriptor implements Identified {
  /// Creates a request port descriptor.
  const RequestPortDescriptor(
    this.id, {
    required this.requestType,
    required this.responseType,
    this.description,
  });

  /// Gets the port identifier.
  @override
  final String id;

  /// Gets the request payload type.
  final Type requestType;

  /// Gets the response payload type.
  final Type responseType;

  /// Gets an optional human-readable description for the port.
  final String? description;

  @override
  bool operator ==(Object other) =>
      other is RequestPortDescriptor &&
      other.id == id &&
      other.requestType == requestType &&
      other.responseType == responseType &&
      other.description == description;

  @override
  int get hashCode => Object.hash(id, requestType, responseType, description);

  @override
  String toString() => id;
}

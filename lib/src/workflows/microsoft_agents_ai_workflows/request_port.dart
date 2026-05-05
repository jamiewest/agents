import 'workflow.dart';

/// An external request port for a [Workflow] with the specified request and
/// response types.
///
/// [Id]
///
/// [Request]
///
/// [Response]
class RequestPort {
  /// An external request port for a [Workflow] with the specified request and
  /// response types.
  ///
  /// [Id]
  ///
  /// [Request]
  ///
  /// [Response]
  const RequestPort(
    String Id,
    Type Request,
    Type Response,
  ) :
      id = Id,
      request = Request,
      response = Response;

  ///
  String id;

  ///
  Type request;

  ///
  Type response;

  /// Creates a new [RequestPort] instance configured for the specified request
  /// and response types.
  ///
  /// Returns: An [RequestPort] instance associated with the specified `id`,
  /// configured to handle requests of type `TRequest` and responses of type
  /// `TResponse`.
  ///
  /// [id] The unique identifier for the input port.
  ///
  /// [TRequest] The type of the request messages that the input port will
  /// accept.
  ///
  /// [TResponse] The type of the response messages that the input port will
  /// produce.
  static RequestPort<TRequest, TResponse> create<TRequest,TResponse>(String id) {
    return new(id, TRequest, TResponse);
  }

  @override
  bool operator ==(Object other) { if (identical(this, other)) return true;
    return other is RequestPort &&
    id == other.id &&
    request == other.request &&
    response == other.response; }
  @override
  int get hashCode { return Object.hash(id, request, response); }
}
/// An external request port for a [Workflow] with the specified request and
/// response types.
///
/// [Id]
///
/// [Request]
///
/// [Response]
///
/// [AllowWrapped]
class RequestPort<TRequest,TResponse> extends RequestPort {
  /// An external request port for a [Workflow] with the specified request and
  /// response types.
  ///
  /// [Id]
  ///
  /// [Request]
  ///
  /// [Response]
  ///
  /// [AllowWrapped]
  RequestPort(String Id, Type Request, Type Response, {bool? AllowWrapped = null, });

  ///
  bool allowWrapped;

}

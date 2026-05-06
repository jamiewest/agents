import 'type_id.dart';

/// Information about an input port, including its input and output types.
///
/// [RequestType]
///
/// [ResponseType]
///
/// [PortId]
class RequestPortInfo {
  /// Information about an input port, including its input and output types.
  ///
  /// [RequestType]
  ///
  /// [ResponseType]
  ///
  /// [PortId]
  const RequestPortInfo(TypeId RequestType, TypeId ResponseType, String PortId)
    : requestType = RequestType,
      responseType = ResponseType,
      portId = PortId;

  ///
  final TypeId requestType;

  ///
  final TypeId responseType;

  ///
  final String portId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RequestPortInfo &&
        requestType == other.requestType &&
        responseType == other.responseType &&
        portId == other.portId;
  }

  @override
  int get hashCode {
    return Object.hash(requestType, responseType, portId);
  }
}

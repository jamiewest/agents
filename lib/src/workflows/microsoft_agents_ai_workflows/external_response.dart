import 'checkpointing/request_port_info.dart';
import 'portable_value.dart';

/// Represents a request from an external input port.
///
/// [PortInfo] The port invoked.
///
/// [RequestId] The unique identifier of the corresponding request.
///
/// [Data] The data contained in the response.
class ExternalResponse {
  /// Represents a request from an external input port.
  ///
  /// [PortInfo] The port invoked.
  ///
  /// [RequestId] The unique identifier of the corresponding request.
  ///
  /// [Data] The data contained in the response.
  const ExternalResponse(
    RequestPortInfo PortInfo,
    String RequestId,
    PortableValue Data,
  ) :
      portInfo = PortInfo,
      requestId = RequestId,
      data = Data;

  /// The port invoked.
  RequestPortInfo portInfo;

  /// The unique identifier of the corresponding request.
  String requestId;

  /// The data contained in the response.
  PortableValue data;

  /// Determines whether the underlying data is of the specified type.
  ///
  /// Returns: true if the underlying data is of type TValue; otherwise, false.
  ///
  /// [TValue] The type to compare with the underlying data.
  bool isDataOfType<TValue>() {
    return this.data.isValue<TValue>();
  }

  /// Determines whether the underlying data can be retrieved as the specified
  /// type.
  ///
  /// Returns: true if the data is present and can be cast to `TValue`;
  /// otherwise, false.
  ///
  /// [value] When this method returns, contains the value of type `TValue` if
  /// the data is available and compatible.
  ///
  /// [TValue] The type to which the underlying data is to be cast if available.
  bool tryGetDataAs<TValue>({TValue? value, Type? targetType, }) {
    return this.data.isValue(value);
  }

  @override
  bool operator ==(Object other) { if (identical(this, other)) return true;
    return other is ExternalResponse &&
    portInfo == other.portInfo &&
    requestId == other.requestId &&
    data == other.data; }
  @override
  int get hashCode { return Object.hash(portInfo, requestId, data); }
}

import 'checkpointing/request_port_info.dart';
import 'request_port.dart';
import 'external_response.dart';
import 'portable_value.dart';

/// Represents a request to an external input port.
///
/// [PortInfo] The port to invoke.
///
/// [RequestId] A unique identifier for this request instance.
///
/// [Data] The data contained in the request.
class ExternalRequest {
  /// Represents a request to an external input port.
  ///
  /// [PortInfo] The port to invoke.
  ///
  /// [RequestId] A unique identifier for this request instance.
  ///
  /// [Data] The data contained in the request.
  const ExternalRequest(
    RequestPortInfo PortInfo,
    String RequestId,
    PortableValue Data,
  ) :
      portInfo = PortInfo,
      requestId = RequestId,
      data = Data;

  /// The port to invoke.
  RequestPortInfo portInfo;

  /// A unique identifier for this request instance.
  String requestId;

  /// The data contained in the request.
  PortableValue data;

  /// Determines whether the underlying data is of the specified type.
  ///
  /// Returns: true if the underlying data is of type TValue; otherwise, false.
  ///
  /// [TValue] The type to compare with the underlying data.
  bool isDataOfType<TValue>() {
    return this.data.isValue<TValue>();
  }

  /// Determines whether the underlying data is of the specified type and
  /// outputs the value if it is.
  ///
  /// Returns: true if the underlying data is of type TValue; otherwise, false.
  ///
  /// [TValue] The type to compare with the underlying data.
  bool tryGetDataAs<TValue>({TValue? value, Type? targetType, }) {
    return this.data.isValue(value);
  }

  /// Creates a new [ExternalRequest] for the specified input port and data
  /// payload.
  ///
  /// Returns: An [ExternalRequest] instance containing the specified port,
  /// data, and request identifier.
  ///
  /// [port] The port to invoke.
  ///
  /// [data] The data contained in the request.
  ///
  /// [requestId] An optional unique identifier for this request instance. If
  /// `null`, a UUID will be generated.
  static ExternalRequest create(RequestPort port, String? requestId, {Object? data, }) {
    // TODO(ai): implement dispatch
    throw UnimplementedError();
  }

  /// Creates a new [ExternalResponse] corresponding to the request, with the
  /// speicified data payload.
  ///
  /// Returns: An [ExternalResponse] instance corresponding to this request with
  /// the specified data.
  ///
  /// [data] The data contained in the response.
  ExternalResponse createResponse({Object? data}) {
    // TODO(ai): implement dispatch
    throw UnimplementedError();
  }

  ExternalResponse rewrapResponse(ExternalResponse response) {
    return externalResponse(this.portInfo, this.requestId, response.data);
  }

  @override
  bool operator ==(Object other) { if (identical(this, other)) return true;
    return other is ExternalRequest &&
    portInfo == other.portInfo &&
    requestId == other.requestId &&
    data == other.data; }
  @override
  int get hashCode { return Object.hash(portInfo, requestId, data); }
}

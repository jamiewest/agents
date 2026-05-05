import 'executor_binding.dart';
import 'request_port.dart';

/// Represents the registration details for a request port, including
/// configuration for allowing wrapped requests.
///
/// [Port] The request port.
///
/// [AllowWrapped] true to allow wrapped requests to be handled by the port;
/// otherwise, false. The default is true.
class RequestPortBinding extends ExecutorBinding {
  /// Represents the registration details for a request port, including
  /// configuration for allowing wrapped requests.
  ///
  /// [Port] The request port.
  ///
  /// [AllowWrapped] true to allow wrapped requests to be handled by the port;
  /// otherwise, false. The default is true.
  RequestPortBinding(RequestPort Port, {bool? AllowWrapped = null})
    : port = Port;

  /// The request port.
  RequestPort port;

  /// true to allow wrapped requests to be handled by the port; otherwise,
  /// false. The default is true.
  bool allowWrapped;

  bool get isSharedInstance {
    return false;
  }

  bool get supportsConcurrentSharedExecution {
    return true;
  }

  bool get supportsResetting {
    return false;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RequestPortBinding &&
        port == other.port &&
        allowWrapped == other.allowWrapped;
  }

  @override
  int get hashCode {
    return Object.hash(port, allowWrapped);
  }
}

/// Well-known values for the `network` parameter on [DockerShellExecutor].
///
/// The parameter type stays [String] so callers can supply user-defined
/// networks (e.g. `'my-private-net'`). These constants exist for
/// discoverability.
abstract final class DockerNetworkMode {
  /// No network — the container has no network interfaces. The default.
  static const String none = 'none';

  /// Docker's default bridge network — egress to the host network.
  static const String bridge = 'bridge';

  /// Share the host's network namespace — strongly discouraged for untrusted code.
  static const String host = 'host';
}

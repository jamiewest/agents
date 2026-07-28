import 'navigation_network_stub.dart'
    if (dart.library.io) 'navigation_network_io.dart'
    as network;

/// Resolves a host name into textual IP addresses.
typedef WebHostResolver = Future<List<String>> Function(String host);

/// A decision returned by [WebNavigationPolicy].
class WebNavigationDecision {
  const WebNavigationDecision._(this.allowed, this.reason);

  /// Allows the requested navigation.
  const WebNavigationDecision.allow() : this._(true, null);

  /// Blocks the requested navigation with a safe [reason].
  const WebNavigationDecision.block(String reason) : this._(false, reason);

  /// Whether navigation may continue.
  final bool allowed;

  /// Safe explanation when [allowed] is false.
  final String? reason;
}

/// Decides whether the embedded browser may request a URL.
abstract interface class WebNavigationPolicy {
  /// Evaluates [url] before it is requested.
  Future<WebNavigationDecision> evaluate(Uri url);
}

/// Allows public HTTP(S) destinations and blocks local or private targets.
///
/// This policy rejects credentials, localhost-style names, and any host whose
/// resolved address is loopback, private, link-local, multicast, unspecified,
/// or otherwise non-public.
class PublicWebNavigationPolicy implements WebNavigationPolicy {
  /// Creates a public-web policy.
  ///
  /// [hostResolver] is injectable for deterministic tests. The default uses
  /// the platform DNS resolver and is unavailable on Flutter web.
  PublicWebNavigationPolicy({WebHostResolver? hostResolver})
    : _hostResolver = hostResolver ?? network.resolveHost;

  final WebHostResolver _hostResolver;

  @override
  Future<WebNavigationDecision> evaluate(Uri url) async {
    final scheme = url.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return const WebNavigationDecision.block(
        'Only HTTP and HTTPS URLs are allowed.',
      );
    }
    if (!url.hasAuthority || url.host.isEmpty) {
      return const WebNavigationDecision.block('The URL must contain a host.');
    }
    if (url.userInfo.isNotEmpty) {
      return const WebNavigationDecision.block(
        'URLs containing embedded credentials are not allowed.',
      );
    }

    final host = url.host.toLowerCase();
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local')) {
      return const WebNavigationDecision.block(
        'Local host names are not allowed.',
      );
    }

    final List<String> addresses;
    try {
      addresses = await _hostResolver(host);
    } on UnsupportedError {
      rethrow;
    } catch (_) {
      return const WebNavigationDecision.block(
        'The URL host could not be resolved.',
      );
    }
    if (addresses.isEmpty) {
      return const WebNavigationDecision.block(
        'The URL host did not resolve to an address.',
      );
    }
    if (addresses.any((address) => !network.isPublicAddress(address))) {
      return const WebNavigationDecision.block(
        'Local, private, or non-public network addresses are not allowed.',
      );
    }
    return const WebNavigationDecision.allow();
  }
}

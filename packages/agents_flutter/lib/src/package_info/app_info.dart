library;

/// Holds the app's package metadata, loaded once at startup.
///
/// Populated by [PackageInfoHostedService] during host startup (or the
/// direct, hostless path) and read by the `get_app_info` tool. Registered as
/// a singleton so the writer and the tool share the same instance. Plain
/// typed fields keep the plugin's `PackageInfo` type out of the public API,
/// matching how `DeviceInfo` translates plugin data.
class AppInfo {
  String? _appName;
  String? _packageName;
  String? _version;
  String? _buildNumber;

  /// Whether the metadata has been loaded yet.
  bool get isReady => _appName != null;

  /// The app's display name, or `null` until loading completes.
  String? get appName => _appName;

  /// The package/bundle identifier, or `null` until loading completes.
  String? get packageName => _packageName;

  /// The version string, or `null` until loading completes.
  String? get version => _version;

  /// The build number, or `null` until loading completes.
  String? get buildNumber => _buildNumber;

  /// Stores the loaded package metadata.
  void populate({
    required String appName,
    required String packageName,
    required String version,
    required String buildNumber,
  }) {
    _appName = appName;
    _packageName = packageName;
    _version = version;
    _buildNumber = buildNumber;
  }

  /// Returns the app metadata as model-friendly `key: value` lines.
  ///
  /// Falls back to a clear message when called before loading completes.
  String describe() {
    if (!isReady) {
      return 'App info is not available yet.';
    }
    return 'App name: $_appName\n'
        'Package id: $_packageName\n'
        'Version: $_version\n'
        'Build number: $_buildNumber';
  }
}

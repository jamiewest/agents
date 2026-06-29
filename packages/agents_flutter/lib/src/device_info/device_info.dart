library;

/// Holds device information gathered once at startup.
///
/// [DeviceInfoHostedService] populates this from `device_info_plus` during
/// boot, and the `get_device_info` tool reads it on demand. The value is set
/// once and never changes, so no [ChangeNotifier] is needed.
class DeviceInfo {
  Map<String, String>? _fields;

  /// Whether the device information has been gathered yet.
  bool get isReady => _fields != null;

  /// A short, human-friendly device name for display and LAN advertising.
  ///
  /// Falls back through the platform-specific name keys populated by
  /// [DeviceInfoHostedService], then to a generic label.
  String get displayName {
    final fields = _fields;
    if (fields == null) return 'This device';
    return fields['Device'] ??
        fields['Computer'] ??
        fields['Model'] ??
        fields['System'] ??
        'This device';
  }

  /// A compact one-line device summary for always-on context, e.g.
  /// `MacBook Pro, macOS 15.5`.
  ///
  /// Returns null until the fields are gathered, so callers can omit the line
  /// entirely rather than inject a placeholder. Combines [displayName] with the
  /// platform `System` field when present.
  String? get summary {
    final fields = _fields;
    if (fields == null) return null;
    final system = fields['System'];
    return system == null ? displayName : '$displayName, $system';
  }

  /// Stores the gathered key/value device fields.
  void populate(Map<String, String> fields) {
    _fields = Map.unmodifiable(fields);
  }

  /// Returns the device information as model-friendly `key: value` lines.
  ///
  /// Falls back to a clear message when called before the data is gathered.
  String describe() {
    final fields = _fields;
    if (fields == null || fields.isEmpty) {
      return 'Device information is not available yet.';
    }
    return fields.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  }
}

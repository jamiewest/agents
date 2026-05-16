/// Helpers for the `cleanEnvironment` mode where the spawned shell does not
/// inherit the parent process environment — except for a small allowlist of
/// variables that the shell needs to locate itself and basic tools.
class EnvironmentSanitizer {
  EnvironmentSanitizer._();

  /// Variables propagated from the host environment when `cleanEnvironment`
  /// is `true`. Lookup is case-insensitive so it works on both Windows
  /// (case-insensitive env vars) and POSIX.
  static const List<String> preservedVariables = [
    'PATH',
    'HOME',
    'USER',
    'USERNAME',
    'USERPROFILE',
    'SystemRoot',
    'TEMP',
    'TMP',
  ];

  /// Strips everything from [environment] except entries named by
  /// [preservedVariables]. Case-insensitive matching.
  static void removeNonPreserved(Map<String, String> environment) {
    final keep = <String, String>{};
    final preserved = {
      for (final k in preservedVariables) k.toLowerCase(): k,
    };
    for (final entry in environment.entries) {
      final lower = entry.key.toLowerCase();
      if (preserved.containsKey(lower)) {
        keep[entry.key] = entry.value;
      }
    }
    environment
      ..clear()
      ..addAll(keep);
  }
}

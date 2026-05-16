/// UID/GID pair passed to `docker run --user`.
final class ContainerUser {
  /// Creates a [ContainerUser] with the given [uid] and [gid].
  const ContainerUser(this.uid, this.gid);

  /// Default unprivileged user (`nobody:nogroup` on most distros, UID/GID 65534).
  static const ContainerUser defaultUser = ContainerUser('65534', '65534');

  /// Container root (UID/GID 0). Avoid in production; use only for diagnostics.
  static const ContainerUser root = ContainerUser('0', '0');

  /// User ID (numeric string, e.g. `'65534'`; `'root'` or `'0'` selects the
  /// container's root user).
  final String uid;

  /// Group ID (numeric string).
  final String gid;

  /// Returns `true` when this user maps to UID 0 (root).
  bool get isRoot {
    if (uid.toLowerCase() == 'root') return true;
    final parsed = int.tryParse(uid);
    return parsed != null && parsed == 0;
  }

  /// Render as the `uid:gid` string Docker expects.
  @override
  String toString() => '$uid:$gid';
}

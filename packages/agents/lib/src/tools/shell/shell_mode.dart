/// Specifies how a shell executor dispatches commands to the underlying shell.
enum ShellMode {
  /// Each command runs in a fresh shell subprocess. State (working directory,
  /// environment variables) is reset between calls.
  stateless,

  /// A single long-lived shell subprocess is reused across calls so `cd` and
  /// exported variables persist between invocations. Commands are executed via
  /// a sentinel protocol that brackets stdout to determine completion. This is
  /// the recommended default for coding agents.
  ///
  /// A persistent-mode executor is intended to be owned by exactly one
  /// conversation/agent session. Sharing one instance across users or
  /// concurrent conversations leaks state between them.
  persistent,
}

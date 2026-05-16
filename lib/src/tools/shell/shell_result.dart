/// The outcome of a single shell command invocation.
final class ShellResult {
  /// Creates a [ShellResult].
  const ShellResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duration,
    this.truncated = false,
    this.timedOut = false,
  });

  /// Captured standard output, possibly truncated.
  final String stdout;

  /// Captured standard error, possibly truncated.
  final String stderr;

  /// The exit status reported by the shell or subprocess. `-1` if the process
  /// never exited cleanly.
  final int exitCode;

  /// How long the command took to execute end-to-end.
  final Duration duration;

  /// `true` when stdout or stderr was truncated.
  final bool truncated;

  /// `true` when the command was killed because it exceeded the configured
  /// timeout.
  final bool timedOut;

  /// Format the result as a single text block suitable for return to a
  /// language model.
  String formatForModel() {
    final sb = StringBuffer();
    if (stdout.isNotEmpty) {
      sb.write(stdout);
      if (truncated) {
        sb.writeln();
        sb.write('[stdout truncated]');
      }
      sb.writeln();
    }
    if (stderr.isNotEmpty) {
      sb.write('stderr: ');
      sb.write(stderr);
      sb.writeln();
    }
    if (timedOut) {
      sb.writeln('[command timed out]');
    }
    sb.write('exit_code: ');
    sb.write(exitCode);
    return sb.toString();
  }
}

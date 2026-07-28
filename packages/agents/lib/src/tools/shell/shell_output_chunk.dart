/// Identifies the process stream that produced a [ShellOutputChunk].
enum ShellOutputChannel {
  /// Standard output.
  stdout,

  /// Standard error.
  stderr,
}

/// A live line of output produced while a shell command is running.
///
/// [text] includes a trailing newline. [commandId] is unique within one shell
/// executor instance and lets consumers separate output from concurrent
/// stateless commands.
final class ShellOutputChunk {
  /// Creates a shell output chunk.
  const ShellOutputChunk({
    required this.commandId,
    required this.command,
    required this.channel,
    required this.text,
  });

  /// Monotonically increasing command identifier scoped to one executor.
  final int commandId;

  /// The command that produced this output.
  final String command;

  /// Whether this chunk came from stdout or stderr.
  final ShellOutputChannel channel;

  /// The emitted line, including a trailing newline.
  final String text;
}

/// Receives live shell output as a command executes.
typedef ShellOutputCallback = void Function(ShellOutputChunk chunk);

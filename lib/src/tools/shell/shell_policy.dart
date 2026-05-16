/// A shell command awaiting a policy decision.
final class ShellRequest {
  /// Creates a [ShellRequest] for the given [command] and optional
  /// [workingDirectory].
  const ShellRequest(this.command, {this.workingDirectory});

  /// The full command line that the agent wants to run.
  final String command;

  /// Optional working directory the command will execute in, if known.
  final String? workingDirectory;

  @override
  bool operator ==(Object other) =>
      other is ShellRequest &&
      command == other.command &&
      workingDirectory == other.workingDirectory;

  @override
  int get hashCode => Object.hash(command, workingDirectory);
}

/// The result of a [ShellPolicy] evaluation.
final class ShellPolicyOutcome {
  const ShellPolicyOutcome({required this.allowed, this.reason});

  /// A singleton outcome representing an allowed command.
  static const ShellPolicyOutcome allow = ShellPolicyOutcome(allowed: true);

  /// Whether the command is allowed to run.
  final bool allowed;

  /// Optional human-readable explanation, populated on denial.
  final String? reason;
}

/// Evaluates shell commands against configurable allow/deny regex patterns.
///
/// **This is a UX guardrail, not a security boundary.** Regex patterns can be
/// bypassed through variable indirection and other shell tricks. The real
/// security controls are approval-in-the-loop and Docker container isolation.
/// Use [ShellPolicy] to provide a better user experience by catching common
/// accidental destructive commands; do not rely on it to stop a determined
/// adversary.
///
/// Evaluation order:
/// 1. Empty command → deny.
/// 2. Allow list match → allow (overrides deny list).
/// 3. Deny list match → deny.
/// 4. Default → allow.
class ShellPolicy {
  /// Creates a [ShellPolicy] with optional [allowList] and [denyList] regex
  /// patterns. Patterns are compiled once at construction time.
  ShellPolicy({
    Iterable<String>? allowList,
    Iterable<String>? denyList,
  })  : _allowList = allowList?.map(RegExp.new).toList(),
        _denyList = denyList?.map(RegExp.new).toList();

  final List<RegExp>? _allowList;
  final List<RegExp>? _denyList;

  /// Evaluates [request] and returns the policy outcome.
  ShellPolicyOutcome evaluate(ShellRequest request) {
    if (request.command.trim().isEmpty) {
      return const ShellPolicyOutcome(
        allowed: false,
        reason: 'Command is empty.',
      );
    }

    final cmd = request.command;

    if (_allowList != null) {
      for (final pattern in _allowList) {
        if (pattern.hasMatch(cmd)) return ShellPolicyOutcome.allow;
      }
    }

    if (_denyList != null) {
      for (final pattern in _denyList) {
        if (pattern.hasMatch(cmd)) {
          return const ShellPolicyOutcome(
            allowed: false,
            reason: 'Command matched deny pattern.',
          );
        }
      }
    }

    return ShellPolicyOutcome.allow;
  }
}

/// Thrown by a [ShellExecutor] when a [ShellPolicy] denies a command.
class ShellCommandRejectedException implements Exception {
  /// Creates a [ShellCommandRejectedException] for the given [command].
  const ShellCommandRejectedException(this.command, {this.reason});

  /// The command that was rejected.
  final String command;

  /// The policy reason for rejection, if available.
  final String? reason;

  @override
  String toString() {
    final msg = 'ShellCommandRejectedException: Command rejected: $command';
    return reason != null ? '$msg ($reason)' : msg;
  }
}

import 'workflow.dart';

/// Represents a workflow session.
class WorkflowSession {
  /// Creates a workflow session.
  WorkflowSession({required this.workflow, String? sessionId})
    : sessionId = sessionId ?? createSessionId();

  /// Gets the workflow for this session.
  final Workflow workflow;

  /// Gets the unique session identifier.
  final String sessionId;

  /// Creates a session identifier.
  static String createSessionId() =>
      'session-${DateTime.now().microsecondsSinceEpoch}';

  @override
  String toString() => sessionId;
}

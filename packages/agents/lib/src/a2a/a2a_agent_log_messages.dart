import 'package:extensions/logging.dart';

/// Logging extensions for [A2AAgent] invocations.
extension A2AAgentLogMessages on Logger {
  /// Logs that an [A2AAgent] is about to invoke the underlying A2A agent.
  void logA2AAgentInvokingAgent(
    String methodName,
    String agentId,
    String? agentName,
  ) {
    if (!isEnabled(LogLevel.debug)) return;
    logDebug(
      '[$methodName] A2AAgent $agentId/${agentName ?? ''} '
      'invoking underlying A2A agent.',
    );
  }

  /// Logs that an [A2AAgent] has completed invoking the underlying A2A agent.
  void logA2AAgentInvokedAgent(
    String methodName,
    String agentId,
    String? agentName,
  ) {
    if (!isEnabled(LogLevel.information)) return;
    logInformation(
      '[$methodName] A2AAgent $agentId/${agentName ?? ''} '
      'invoked underlying A2A agent.',
    );
  }

  /// Logs a warning when [A2AAgent] falls back from SubscribeToTask to
  /// GetTask after receiving an UnsupportedOperation error.
  void logA2ASubscribeToTaskFallback(
    String agentId,
    String? agentName,
    String taskId,
    String errorMessage,
  ) {
    logWarning(
      'A2AAgent $agentId/${agentName ?? ''} SubscribeToTask for task '
      "'$taskId' failed with UnsupportedOperation: $errorMessage. "
      'Falling back to GetTask.',
    );
  }
}

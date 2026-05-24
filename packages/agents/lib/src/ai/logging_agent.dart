import 'dart:convert';

import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import '../abstractions/agent_response.dart';
import '../abstractions/agent_response_update.dart';
import '../abstractions/agent_run_options.dart';
import '../abstractions/agent_session.dart';
import '../abstractions/ai_agent.dart';
import '../abstractions/ai_agent_metadata.dart';
import '../abstractions/delegating_ai_agent.dart';

/// A delegating [AIAgent] that logs agent operations to a [Logger].
///
/// When [LogLevel.trace] is enabled, message contents, options, and responses
/// are included in the log output. These may contain sensitive data. Trace
/// logging should never be enabled in production.
class LoggingAgent extends DelegatingAIAgent {
  /// Creates a [LoggingAgent] wrapping [innerAgent] and logging to [logger].
  LoggingAgent(super.innerAgent, Logger logger) : _logger = logger;

  final Logger _logger;

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    if (_logger.isEnabled(LogLevel.debug)) {
      if (_logger.isEnabled(LogLevel.trace)) {
        _logInvokedSensitive(
          'runCore',
          _asJson(messages),
          _asJson(options),
          _asJson(getService(AIAgentMetadata)),
        );
      } else {
        _logInvoked('runCore');
      }
    }

    try {
      final response = await innerAgent.runCore(
        messages,
        session: session,
        options: options,
        cancellationToken: cancellationToken,
      );
      if (_logger.isEnabled(LogLevel.debug)) {
        if (_logger.isEnabled(LogLevel.trace)) {
          _logCompletedSensitive('runCore', _asJson(response));
        } else {
          _logCompleted('runCore');
        }
      }
      return response;
    } catch (ex) {
      _logInvocationFailed('runCore', ex);
      rethrow;
    }
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    if (_logger.isEnabled(LogLevel.debug)) {
      if (_logger.isEnabled(LogLevel.trace)) {
        _logInvokedSensitive(
          'runCoreStreaming',
          _asJson(messages),
          _asJson(options),
          _asJson(getService(AIAgentMetadata)),
        );
      } else {
        _logInvoked('runCoreStreaming');
      }
    }

    try {
      await for (final update in innerAgent.runCoreStreaming(
        messages,
        session: session,
        options: options,
        cancellationToken: cancellationToken,
      )) {
        if (_logger.isEnabled(LogLevel.trace)) {
          _logStreamingUpdateSensitive(_asJson(update));
        }
        yield update;
      }
      _logCompleted('runCoreStreaming');
    } catch (ex) {
      _logInvocationFailed('runCoreStreaming', ex);
      rethrow;
    }
  }

  String _asJson(Object? value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return value?.toString() ?? 'null';
    }
  }

  void _logInvoked(String methodName) {
    _logger.logDebug('Agent invoked. Method: $methodName.');
  }

  void _logInvokedSensitive(
    String methodName,
    String messages,
    String options,
    String metadata,
  ) {
    _logger.logTrace(
      'Agent invoked. Method: $methodName. '
      'Messages: $messages. Options: $options. Metadata: $metadata.',
    );
  }

  void _logCompleted(String methodName) {
    _logger.logDebug('Agent completed. Method: $methodName.');
  }

  void _logCompletedSensitive(String methodName, String response) {
    _logger.logTrace(
      'Agent completed. Method: $methodName. Response: $response.',
    );
  }

  void _logStreamingUpdateSensitive(String update) {
    _logger.logTrace('Agent streaming update. $update.');
  }

  void _logInvocationFailed(String methodName, Object error) {
    _logger.logError(
      'Agent invocation failed. Method: $methodName.',
      error: error,
    );
  }
}

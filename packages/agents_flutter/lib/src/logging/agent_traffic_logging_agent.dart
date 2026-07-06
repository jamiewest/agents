// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents/agents.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

/// The logger category used by [AgentTrafficLoggingAgent].
const String agentTrafficLogCategory = 'Agents.Traffic';

/// A delegating [AIAgent] that logs one concise summary per run.
///
/// Unlike the framework's `LoggingAgent` — whose trace level emits a log
/// entry for every streamed update — this decorator aggregates a streamed
/// run and logs a single completion record, so enabling it never floods the
/// log with per-token noise.
///
/// Levels:
/// - `debug`: run started (message count).
/// - `information`: run completed (duration, update count, response size).
/// - `trace`: the request and final response text are included verbatim.
///   Payloads may contain sensitive data; keep trace off in production.
/// - `error`: the run failed.
class AgentTrafficLoggingAgent extends DelegatingAIAgent {
  /// Wraps [innerAgent], logging run summaries to [logger].
  AgentTrafficLoggingAgent(super.innerAgent, Logger logger) : _logger = logger;

  final Logger _logger;

  String get _label {
    final agentName = innerAgent.name;
    return agentName == null || agentName.isEmpty
        ? 'agent ${innerAgent.id}'
        : 'agent "$agentName"';
  }

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final messageList = messages.toList();
    _logStart(messageList);
    final stopwatch = Stopwatch()..start();
    try {
      final response = await innerAgent.runCore(
        messageList,
        session: session,
        options: options,
        cancellationToken: cancellationToken,
      );
      _logCompleted(
        stopwatch.elapsed,
        responseText: response.text,
        updateCount: null,
      );
      return response;
    } catch (error) {
      _logFailed(stopwatch.elapsed, error);
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
    final messageList = messages.toList();
    _logStart(messageList);
    final stopwatch = Stopwatch()..start();
    var updateCount = 0;
    final responseText = StringBuffer();
    try {
      await for (final update in innerAgent.runCoreStreaming(
        messageList,
        session: session,
        options: options,
        cancellationToken: cancellationToken,
      )) {
        updateCount++;
        for (final content in update.contents) {
          if (content is TextContent) responseText.write(content.text);
        }
        yield update;
      }
      _logCompleted(
        stopwatch.elapsed,
        responseText: responseText.toString(),
        updateCount: updateCount,
      );
    } catch (error) {
      _logFailed(stopwatch.elapsed, error);
      rethrow;
    }
  }

  void _logStart(List<ChatMessage> messages) {
    if (_logger.isEnabled(LogLevel.trace)) {
      _logger.logTrace(
        '$_label run started (${messages.length} messages)\n'
        '${_renderMessages(messages)}',
      );
    } else {
      _logger.logDebug('$_label run started (${messages.length} messages)');
    }
  }

  void _logCompleted(
    Duration elapsed, {
    required String responseText,
    required int? updateCount,
  }) {
    final streamed = updateCount == null ? '' : ', $updateCount updates';
    final summary =
        '$_label responded in ${elapsed.inMilliseconds}ms'
        '$streamed, ${responseText.length} chars';
    if (_logger.isEnabled(LogLevel.trace)) {
      _logger.logTrace('$summary\n$responseText');
    } else {
      _logger.logInformation(summary);
    }
  }

  void _logFailed(Duration elapsed, Object error) {
    _logger.logError(
      '$_label run failed after ${elapsed.inMilliseconds}ms: $error',
      error: error,
    );
  }

  static String _renderMessages(List<ChatMessage> messages) {
    final buffer = StringBuffer();
    for (final message in messages) {
      buffer.writeln('[${message.role.value}]');
      final text = message.text.trim();
      if (text.isNotEmpty) buffer.writeln(text);
    }
    return buffer.toString().trimRight();
  }
}

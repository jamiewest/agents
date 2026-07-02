import 'dart:collection';
import 'dart:math';

import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/agent_response.dart';
import '../../../abstractions/agent_response_extensions.dart';
import '../../../abstractions/agent_response_update.dart';
import '../../../abstractions/agent_run_options.dart';
import '../../../abstractions/agent_session.dart';
import '../../../abstractions/ai_agent.dart';
import '../../../abstractions/delegating_ai_agent.dart';
import 'loop_agent_options.dart';
import 'loop_context.dart';
import 'loop_evaluation.dart';
import 'loop_evaluator.dart';

/// A [DelegatingAIAgent] that re-invokes the wrapped agent in a loop until the
/// configured [LoopEvaluator] set decides to stop.
///
/// After each run of the wrapped agent, the configured evaluators are asked
/// whether to re-invoke the agent and what feedback to carry forward. When
/// multiple evaluators are supplied they are evaluated in order; the first
/// evaluator that asks to re-invoke wins, its feedback drives the next
/// iteration, and the remaining evaluators are not evaluated. The loop stops
/// only when every evaluator asks to stop, so evaluator order is priority order.
///
/// The caller's initial messages are sent to the wrapped agent exactly once. By
/// default (when [LoopAgentOptions.freshContextPerIteration] is `false`) the
/// loop reuses a single session and sends only the winning evaluator's feedback
/// as the next input. When fresh context is enabled, each re-invocation restarts
/// from the original input plus an aggregated feedback log and the session is
/// reset. An evaluator may instead supply the exact next messages via
/// [LoopEvaluation.proceedWithMessages].
///
/// The loop is bounded by a global safety cap
/// ([LoopAgentOptions.maxIterations]). If an iteration produces a pending
/// tool-approval request, the loop stops and returns that response rather than
/// resolving the approval automatically.
class LoopAgent extends DelegatingAIAgent {
  /// The default value used for [LoopAgentOptions.maxIterations] when none is
  /// specified.
  static const int defaultMaxIterations = 10;

  static final Random _random = Random();

  /// Creates a [LoopAgent] with a single [evaluator].
  LoopAgent(
    AIAgent innerAgent,
    LoopEvaluator evaluator, {
    LoopAgentOptions? options,
    LoggerFactory? loggerFactory,
  }) : this.withEvaluators(
         innerAgent,
         [evaluator],
         options: options,
         loggerFactory: loggerFactory,
       );

  /// Creates a [LoopAgent] with one or more [evaluators], evaluated in order.
  ///
  /// Throws [ArgumentError] if [evaluators] is empty, or [RangeError] if
  /// [LoopAgentOptions.maxIterations] is less than 1.
  LoopAgent.withEvaluators(
    super.innerAgent,
    Iterable<LoopEvaluator> evaluators, {
    LoopAgentOptions? options,
    LoggerFactory? loggerFactory,
  }) : _evaluators = List<LoopEvaluator>.unmodifiable(evaluators),
       _maxIterations = _checkMaxIterations(
         options?.maxIterations ?? defaultMaxIterations,
       ),
       _freshContextPerIteration = options?.freshContextPerIteration ?? false,
       _onBehalfOfAuthorName = options?.onBehalfOfAuthorName,
       _excludeOnBehalfOfMessages = options?.excludeOnBehalfOfMessages ?? false,
       _nonStreamingReturnsLastResponseOnly =
           options?.nonStreamingReturnsLastResponseOnly ?? false,
       _sessionCreatedCallback = options?.sessionCreatedCallback,
       _logger = (loggerFactory ?? NullLoggerFactory.instance).createLogger(
         'LoopAgent',
       ) {
    if (_evaluators.isEmpty) {
      throw ArgumentError.value(
        evaluators,
        'evaluators',
        'At least one evaluator must be supplied.',
      );
    }
  }

  final List<LoopEvaluator> _evaluators;
  final int _maxIterations;
  final bool _freshContextPerIteration;
  final String? _onBehalfOfAuthorName;
  final bool _excludeOnBehalfOfMessages;
  final bool _nonStreamingReturnsLastResponseOnly;
  final SessionCreatedCallback? _sessionCreatedCallback;
  final Logger _logger;

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final initialMessages = List<ChatMessage>.of(messages);
    final loopSession = await _resolveSession(session, cancellationToken);
    final initialSessionSnapshot = await _snapshotIfNeeded(
      loopSession,
      sessionProvidedByCaller: session != null,
      cancellationToken: cancellationToken,
    );

    LoopContext? context;
    final feedbackLog = <String?>[];
    Iterable<ChatMessage> currentMessages = initialMessages;
    var iteration = 0;
    final transcript = <ChatMessage>[];
    List<ChatMessage> currentSurfaced = const [];

    while (true) {
      final activeSession = context?.session ?? loopSession;
      final response = await innerAgent.run(
        activeSession,
        options,
        messages: currentMessages,
        cancellationToken: cancellationToken,
      );
      iteration++;
      transcript
        ..addAll(currentSurfaced)
        ..addAll(response.messages);

      context ??= LoopContext(
        innerAgent,
        loopSession,
        initialMessages,
        response,
        runOptions: options,
      )..feedback = UnmodifiableListView(feedbackLog);
      context
        ..iteration = iteration
        ..lastResponse = response;

      if (_hasPendingApprovalRequests(response)) {
        return _buildResult(response, transcript);
      }
      if (iteration >= _maxIterations) {
        _logMaxIterationsReached();
        return _buildResult(response, transcript);
      }

      final step = await _evaluateAndBuildNext(
        context,
        feedbackLog,
        initialSessionSnapshot,
        cancellationToken,
      );
      if (!step.shouldContinue) {
        return _buildResult(response, transcript);
      }
      currentMessages = step.messages;
      currentSurfaced = step.surfacedMessages;
    }
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final initialMessages = List<ChatMessage>.of(messages);
    final loopSession = await _resolveSession(session, cancellationToken);
    final initialSessionSnapshot = await _snapshotIfNeeded(
      loopSession,
      sessionProvidedByCaller: session != null,
      cancellationToken: cancellationToken,
    );

    LoopContext? context;
    final feedbackLog = <String?>[];
    Iterable<ChatMessage> currentMessages = initialMessages;
    var iteration = 0;
    List<ChatMessage> currentSurfaced = const [];

    while (true) {
      final activeSession = context?.session ?? loopSession;
      final updates = <AgentResponseUpdate>[];
      var surfacedPending = currentSurfaced.isNotEmpty;

      await for (final update in innerAgent.runStreaming(
        activeSession,
        options,
        messages: currentMessages,
        cancellationToken: cancellationToken,
      )) {
        if (surfacedPending) {
          for (final surfaced in currentSurfaced) {
            yield _createOnBehalfOfUpdate(surfaced, update.responseId);
          }
          surfacedPending = false;
        }
        updates.add(update);
        yield update;
      }

      if (surfacedPending) {
        final fallbackResponseId = _newId();
        for (final surfaced in currentSurfaced) {
          yield _createOnBehalfOfUpdate(surfaced, fallbackResponseId);
        }
      }

      iteration++;
      final response = updates.toAgentResponse();

      context ??= LoopContext(
        innerAgent,
        loopSession,
        initialMessages,
        response,
        runOptions: options,
      )..feedback = UnmodifiableListView(feedbackLog);
      context
        ..iteration = iteration
        ..lastResponse = response;

      if (_hasPendingApprovalRequests(response)) {
        return;
      }
      if (iteration >= _maxIterations) {
        _logMaxIterationsReached();
        return;
      }

      final step = await _evaluateAndBuildNext(
        context,
        feedbackLog,
        initialSessionSnapshot,
        cancellationToken,
      );
      if (!step.shouldContinue) {
        return;
      }
      currentMessages = step.messages;
      currentSurfaced = step.surfacedMessages;
    }
  }

  Future<AgentSession> _resolveSession(
    AgentSession? session,
    CancellationToken? cancellationToken,
  ) async {
    if (session != null) {
      return session;
    }
    final created = await innerAgent.createSession(
      cancellationToken: cancellationToken,
    );
    await _notifyNewSession(created, cancellationToken);
    return created;
  }

  Future<Object?> _snapshotIfNeeded(
    AgentSession session, {
    required bool sessionProvidedByCaller,
    CancellationToken? cancellationToken,
  }) {
    if (!_freshContextPerIteration || !sessionProvidedByCaller) {
      return Future<Object?>.value(null);
    }
    return innerAgent.serializeSession(
      session,
      cancellationToken: cancellationToken,
    );
  }

  Future<_LoopNextStep> _evaluateAndBuildNext(
    LoopContext context,
    List<String?> feedbackLog,
    Object? initialSessionSnapshot,
    CancellationToken? cancellationToken,
  ) async {
    LoopEvaluation? winner;
    for (final evaluator in _evaluators) {
      final evaluation = await evaluator.evaluate(
        context,
        cancellationToken: cancellationToken,
      );
      if (evaluation.shouldReinvoke) {
        winner = evaluation;
        break;
      }
    }

    if (winner == null) {
      return _LoopNextStep.stop();
    }

    if (_freshContextPerIteration) {
      context.session = await _createFreshIterationSession(
        context,
        initialSessionSnapshot,
        cancellationToken,
      );
    }

    feedbackLog.add(winner.feedback);

    final explicitMessages = winner.messages;
    if (explicitMessages != null) {
      return _LoopNextStep.proceed(
        explicitMessages,
        _surfaced(explicitMessages),
      );
    }

    final next = _buildNextMessages(context, feedbackLog);
    return _LoopNextStep.proceed(next.messages, _surfaced(next.surfaced));
  }

  List<ChatMessage> _surfaced(List<ChatMessage> surfaced) =>
      _excludeOnBehalfOfMessages ? const [] : surfaced;

  AgentResponseUpdate _createOnBehalfOfUpdate(
    ChatMessage message,
    String? responseId,
  ) {
    final messageId = message.messageId;
    return AgentResponseUpdate(
        role: message.role,
        contents: List<AIContent>.of(message.contents),
      )
      ..authorName = message.authorName
      ..messageId = (messageId != null && messageId.isNotEmpty)
          ? messageId
          : _newId()
      ..responseId = responseId;
  }

  ({List<ChatMessage> messages, List<ChatMessage> surfaced}) _buildNextMessages(
    LoopContext context,
    List<String?> feedback,
  ) {
    final messages = <ChatMessage>[];
    final surfaced = <ChatMessage>[];

    if (_freshContextPerIteration) {
      messages.addAll(context.initialMessages);
      final feedbackMessage = _buildAggregatedFeedbackMessage(feedback);
      if (feedbackMessage != null) {
        messages.add(feedbackMessage);
        surfaced.add(feedbackMessage);
      }
    } else {
      final latest = feedback.isNotEmpty ? feedback.last : null;
      if (latest != null && latest.trim().isNotEmpty) {
        final feedbackMessage = ChatMessage(
          role: ChatRole.user,
          contents: [TextContent(latest)],
          authorName: _onBehalfOfAuthorName,
          messageId: _newId(),
        );
        messages.add(feedbackMessage);
        surfaced.add(feedbackMessage);
      }
    }

    return (messages: messages, surfaced: surfaced);
  }

  ChatMessage? _buildAggregatedFeedbackMessage(List<String?> feedback) {
    final body = StringBuffer('## Feedback\n');
    var any = false;
    for (final entry in feedback) {
      if (entry != null && entry.trim().isNotEmpty) {
        body
          ..write('\n- ')
          ..write(entry);
        any = true;
      }
    }

    return any
        ? ChatMessage(
            role: ChatRole.user,
            contents: [TextContent(body.toString())],
            authorName: _onBehalfOfAuthorName,
            messageId: _newId(),
          )
        : null;
  }

  AgentResponse _buildResult(
    AgentResponse lastResponse,
    List<ChatMessage> transcript,
  ) {
    if (_nonStreamingReturnsLastResponseOnly) {
      return lastResponse;
    }
    return AgentResponse(messages: List<ChatMessage>.of(transcript))
      ..agentId = lastResponse.agentId
      ..responseId = lastResponse.responseId
      ..createdAt = lastResponse.createdAt
      ..finishReason = lastResponse.finishReason
      ..usage = lastResponse.usage
      ..additionalProperties = lastResponse.additionalProperties
      ..continuationToken = lastResponse.continuationToken;
  }

  static bool _hasPendingApprovalRequests(AgentResponse response) {
    for (final message in response.messages) {
      for (final content in message.contents) {
        if (content is ToolApprovalRequestContent) {
          return true;
        }
      }
    }
    return false;
  }

  void _logMaxIterationsReached() {
    _logger.logInformation(
      'LoopAgent reached the maximum of $_maxIterations iterations and stopped.',
    );
  }

  Future<AgentSession> _createFreshIterationSession(
    LoopContext context,
    Object? initialSessionSnapshot,
    CancellationToken? cancellationToken,
  ) async {
    final session = initialSessionSnapshot != null
        ? await innerAgent.deserializeSession(
            initialSessionSnapshot,
            cancellationToken: cancellationToken,
          )
        : await context.agent.createSession(
            cancellationToken: cancellationToken,
          );
    await _notifyNewSession(session, cancellationToken);
    return session;
  }

  Future<void> _notifyNewSession(
    AgentSession session,
    CancellationToken? cancellationToken,
  ) async {
    final callback = _sessionCreatedCallback;
    if (callback != null) {
      await callback(session, cancellationToken);
    }
  }

  static int _checkMaxIterations(int value) {
    if (value < 1) {
      throw RangeError.value(value, 'maxIterations', 'must be at least 1');
    }
    return value;
  }

  static String _newId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// The loop's decision for the next iteration: stop, or continue with a set of
/// messages.
class _LoopNextStep {
  const _LoopNextStep._(
    this.shouldContinue,
    this.messages,
    this.surfacedMessages,
  );

  final bool shouldContinue;
  final List<ChatMessage> messages;
  final List<ChatMessage> surfacedMessages;

  factory _LoopNextStep.stop() => const _LoopNextStep._(false, [], []);

  factory _LoopNextStep.proceed(
    List<ChatMessage> messages,
    List<ChatMessage> surfacedMessages,
  ) => _LoopNextStep._(true, messages, surfacedMessages);
}

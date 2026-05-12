// ignore_for_file: non_constant_identifier_names
import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/ai/logging_agent.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('LoggingAgent', () {
    group('runCore', () {
      test('delegates to inner agent and returns response', () async {
        final inner = _TestAgent(responseText: 'hello');
        final logger = _CapturingLogger(enabledLevel: LogLevel.none);
        final agent = LoggingAgent(inner, logger);

        final response = await agent.runCore(
          [ChatMessage.fromText(ChatRole.user, 'hi')],
        );

        expect(response.text, 'hello');
        expect(logger.records, isEmpty);
      });

      test('logs debug invoked/completed when debug is enabled', () async {
        final inner = _TestAgent();
        final logger = _CapturingLogger(enabledLevel: LogLevel.debug);
        final agent = LoggingAgent(inner, logger);

        await agent.runCore([ChatMessage.fromText(ChatRole.user, 'hi')]);

        final messages = logger.messages;
        expect(messages.any((m) => m.contains('invoked')), isTrue);
        expect(messages.any((m) => m.contains('completed')), isTrue);
        expect(messages.every((m) => !m.contains('Messages:')), isTrue);
      });

      test('logs trace with message contents when trace is enabled', () async {
        final inner = _TestAgent();
        final logger = _CapturingLogger(enabledLevel: LogLevel.trace);
        final agent = LoggingAgent(inner, logger);

        await agent.runCore([ChatMessage.fromText(ChatRole.user, 'ping')]);

        final messages = logger.messages;
        expect(messages.any((m) => m.contains('Messages:')), isTrue);
        expect(messages.any((m) => m.contains('Response:')), isTrue);
      });

      test('logs error and rethrows on failure', () async {
        final inner = _ThrowingAgent(Exception('boom'));
        final logger = _CapturingLogger(enabledLevel: LogLevel.debug);
        final agent = LoggingAgent(inner, logger);

        await expectLater(
          () => agent.runCore([ChatMessage.fromText(ChatRole.user, 'fail')]),
          throwsA(isA<Exception>()),
        );

        expect(
          logger.records.any(
            (r) => r.logLevel == LogLevel.error && r.state.contains('failed'),
          ),
          isTrue,
        );
      });

      test('passes session, options, and cancellation token to inner', () async {
        final inner = _TestAgent();
        final logger = _CapturingLogger(enabledLevel: LogLevel.none);
        final agent = LoggingAgent(inner, logger);
        final session = _TestSession();
        final options = AgentRunOptions();
        final ct = CancellationToken.none;

        await agent.runCore(
          [],
          session: session,
          options: options,
          cancellationToken: ct,
        );

        expect(inner.lastSession, same(session));
        expect(inner.lastOptions, same(options));
        expect(inner.lastCancellationToken, same(ct));
      });
    });

    group('runCoreStreaming', () {
      test('delegates streaming to inner agent and yields updates', () async {
        final inner = _TestAgent(responseText: 'streamed');
        final logger = _CapturingLogger(enabledLevel: LogLevel.none);
        final agent = LoggingAgent(inner, logger);

        final updates = await agent
            .runCoreStreaming([ChatMessage.fromText(ChatRole.user, 'hi')])
            .toList();

        expect(updates.single.text, 'streamed');
        expect(logger.records, isEmpty);
      });

      test('logs completed after stream ends when debug enabled', () async {
        final inner = _TestAgent();
        final logger = _CapturingLogger(enabledLevel: LogLevel.debug);
        final agent = LoggingAgent(inner, logger);

        await agent
            .runCoreStreaming([ChatMessage.fromText(ChatRole.user, 'hi')])
            .toList();

        expect(logger.messages.any((m) => m.contains('completed')), isTrue);
      });

      test('logs each streaming update when trace is enabled', () async {
        final inner = _TestAgent();
        final logger = _CapturingLogger(enabledLevel: LogLevel.trace);
        final agent = LoggingAgent(inner, logger);

        await agent
            .runCoreStreaming([ChatMessage.fromText(ChatRole.user, 'hi')])
            .toList();

        expect(
          logger.messages.any((m) => m.contains('streaming update')),
          isTrue,
        );
      });

      test('logs error and rethrows on streaming failure', () async {
        final inner = _ThrowingAgent(Exception('stream-boom'));
        final logger = _CapturingLogger(enabledLevel: LogLevel.debug);
        final agent = LoggingAgent(inner, logger);

        await expectLater(
          () => agent
              .runCoreStreaming([ChatMessage.fromText(ChatRole.user, 'fail')])
              .toList(),
          throwsA(isA<Exception>()),
        );

        expect(
          logger.records.any(
            (r) => r.logLevel == LogLevel.error && r.state.contains('failed'),
          ),
          isTrue,
        );
      });

      test('passes all parameters through to inner streaming agent', () async {
        final inner = _TestAgent();
        final logger = _CapturingLogger(enabledLevel: LogLevel.none);
        final agent = LoggingAgent(inner, logger);
        final session = _TestSession();
        final options = AgentRunOptions();
        final ct = CancellationToken.none;

        await agent
            .runCoreStreaming(
              [],
              session: session,
              options: options,
              cancellationToken: ct,
            )
            .toList();

        expect(inner.lastSession, same(session));
        expect(inner.lastOptions, same(options));
        expect(inner.lastCancellationToken, same(ct));
      });
    });

    group('service delegation', () {
      test('getService delegates to inner agent for unknown types', () {
        final inner = _TestAgent();
        final agent = LoggingAgent(inner, _CapturingLogger(enabledLevel: LogLevel.none));

        expect(agent.getService(AIAgent), same(inner));
      });

      test('getService returns self for own type', () {
        final inner = _TestAgent();
        final agent = LoggingAgent(inner, _CapturingLogger(enabledLevel: LogLevel.none));

        expect(agent.getService(LoggingAgent), same(agent));
      });
    });
  });
}

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _LogRecord {
  _LogRecord(this.logLevel, this.state);
  final LogLevel logLevel;
  final String state;
}

class _CapturingLogger implements Logger {
  _CapturingLogger({required this.enabledLevel});

  final LogLevel enabledLevel;
  final List<_LogRecord> records = [];

  List<String> get messages => records.map((r) => r.state).toList();

  @override
  bool isEnabled(LogLevel logLevel) =>
      logLevel.value >= enabledLevel.value && enabledLevel != LogLevel.none;

  @override
  void log<TState>({
    required LogLevel logLevel,
    required EventId eventId,
    required TState state,
    Object? error,
    required LogFormatter<TState> formatter,
  }) {
    if (!isEnabled(logLevel)) return;
    records.add(_LogRecord(logLevel, formatter(state, error)));
  }

  @override
  Disposable? beginScope<TState>(TState state) => null;
}

class _TestAgent extends AIAgent {
  _TestAgent({this.responseText = 'response'});

  final String responseText;
  AgentSession? lastSession;
  AgentRunOptions? lastOptions;
  CancellationToken? lastCancellationToken;

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => {};

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    lastSession = session;
    lastOptions = options;
    lastCancellationToken = cancellationToken;
    return AgentResponse(
      message: ChatMessage.fromText(ChatRole.assistant, responseText),
    );
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    lastSession = session;
    lastOptions = options;
    lastCancellationToken = cancellationToken;
    yield AgentResponseUpdate(role: ChatRole.assistant, content: responseText);
  }
}

class _ThrowingAgent extends AIAgent {
  _ThrowingAgent(this.error);

  final Object error;

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => {};

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async => throw error;

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    throw error;
  }
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}

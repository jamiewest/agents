import 'dart:typed_data';

import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/ai/evaluation/agent_evaluation_extensions.dart';
import 'package:agents/src/ai/evaluation/agent_evaluation_results.dart';
import 'package:agents/src/ai/evaluation/conversation_splitter.dart';
import 'package:agents/src/ai/evaluation/eval_checks.dart';
import 'package:agents/src/ai/evaluation/eval_item.dart';
import 'package:agents/src/ai/evaluation/eval_item_result.dart';
import 'package:agents/src/ai/evaluation/expected_tool_call.dart';
import 'package:agents/src/ai/evaluation/function_evaluator.dart';
import 'package:agents/src/ai/evaluation/local_evaluator.dart';
import 'package:agents/src/ai/evaluation/meai_evaluator_adapter.dart';
import 'package:agents/src/json_stubs.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('ConversationSplitters', () {
    test('last turn and full split conversations', () {
      final conversation = [
        ChatMessage.fromText(ChatRole.system, 'system'),
        ChatMessage.fromText(ChatRole.user, 'first'),
        ChatMessage.fromText(ChatRole.assistant, 'answer one'),
        ChatMessage.fromText(ChatRole.user, 'second'),
        ChatMessage.fromText(ChatRole.assistant, 'answer two'),
      ];

      final (lastQuery, lastResponse) = ConversationSplitters.lastTurn.split(
        conversation,
      );
      expect(lastQuery.map((m) => m.text), [
        'system',
        'first',
        'answer one',
        'second',
      ]);
      expect(lastResponse.map((m) => m.text), ['answer two']);

      final (fullQuery, fullResponse) = ConversationSplitters.full.split(
        conversation,
      );
      expect(fullQuery.map((m) => m.text), ['system', 'first']);
      expect(fullResponse.map((m) => m.text), [
        'answer one',
        'second',
        'answer two',
      ]);
    });
  });

  group('EvalItem', () {
    test('detects image content and creates per-turn items', () {
      final conversation = [
        ChatMessage.fromText(ChatRole.user, 'first'),
        ChatMessage.fromText(ChatRole.assistant, 'answer one'),
        ChatMessage(
          role: ChatRole.user,
          contents: [DataContent(Uint8List(0), mediaType: 'image/png')],
        ),
        ChatMessage.fromText(ChatRole.assistant, 'answer two'),
      ];

      final item = EvalItem(conversation: conversation);
      expect(item.hasImageContent, isTrue);

      final items = EvalItem.perTurnItems(conversation, context: 'grounding');
      expect(items, hasLength(2));
      expect(items.first.query, 'first');
      expect(items.first.response, 'answer one');
      expect(items.last.response, 'answer two');
      expect(items.last.context, 'grounding');
    });
  });

  group('EvalChecks', () {
    test('keyword, expected, non-empty, and image checks return results', () {
      final item = EvalItem(
        response: 'The Azure agent answered with citations.',
        conversation: [
          ChatMessage(
            role: ChatRole.assistant,
            contents: [DataContent(Uint8List(0), mediaType: 'image/jpeg')],
          ),
        ],
      )..expectedOutput = 'agent answered';

      expect(
        EvalChecks.keywordCheck(['azure', 'citations'])(item).passed,
        isTrue,
      );
      expect(EvalChecks.containsExpected()(item).passed, isTrue);
      expect(EvalChecks.nonEmpty(minLength: 10)(item).passed, isTrue);
      expect(EvalChecks.hasImageContent()(item).passed, isTrue);
    });

    test('tool call checks support names and argument subset matching', () {
      final item =
          EvalItem(
              conversation: [
                ChatMessage(
                  role: ChatRole.assistant,
                  contents: [
                    FunctionCallContent(
                      callId: '1',
                      name: 'get_weather',
                      arguments: {
                        'city': 'Seattle',
                        'units': const JsonElement('metric'),
                        'extra': 1,
                      },
                    ),
                  ],
                ),
              ],
            )
            ..expectedToolCalls = [
              ExpectedToolCall(
                'get_weather',
                arguments: {'city': 'Seattle', 'units': 'metric'},
              ),
            ];

      expect(EvalChecks.toolCallsPresent()(item).passed, isTrue);
      expect(EvalChecks.toolCalledCheck(['get_weather'])(item).passed, isTrue);
      expect(
        EvalChecks.toolCalledCheck([
          'missing',
          'get_weather',
        ], mode: ToolCalledMode.any)(item).passed,
        isTrue,
      );
      expect(EvalChecks.toolCallArgsMatch()(item).passed, isTrue);

      item.expectedToolCalls = [
        ExpectedToolCall('get_weather', arguments: {'city': 'Portland'}),
      ];
      expect(EvalChecks.toolCallArgsMatch()(item).passed, isFalse);
    });
  });

  group('LocalEvaluator', () {
    test('runs checks and aggregates pass/fail results', () async {
      final evaluator = LocalEvaluator([
        EvalChecks.nonEmpty(),
        FunctionEvaluator.create(
          'mentions_agent',
          check: (text) => text.contains('agent'),
        ),
      ]);

      final results = await evaluator.evaluate([
        EvalItem(response: 'agent response'),
        EvalItem(response: ''),
      ]);

      expect(results.providerName, 'LocalEvaluator');
      expect(results.total, 2);
      expect(results.passed, 1);
      expect(results.failed, 1);
      expect(results.allPassed, isFalse);
      expect(() => results.assertAllPassed(), throwsStateError);
    });

    test('AgentEvaluationResults itemPassed honors boolean metrics', () {
      final pass = EvaluationResult(
        metrics: {'ok': BooleanMetric('ok', value: true)},
      );
      final fail = EvaluationResult(
        metrics: {'ok': BooleanMetric('ok', value: false)},
      );

      expect(AgentEvaluationResults.itemPassed(pass), isTrue);
      expect(AgentEvaluationResults.itemPassed(fail), isFalse);
    });
  });

  group('MeaiEvaluatorAdapter', () {
    test('splits item and delegates to MEAI evaluator', () async {
      final evaluator = _FakeEvaluator();
      final adapter = MeaiEvaluatorAdapter(
        evaluator,
        ChatConfiguration(_FakeChatClient()),
      );
      final item = EvalItem(
        response: 'model answer',
        conversation: [
          ChatMessage.fromText(ChatRole.user, 'question'),
          ChatMessage.fromText(ChatRole.assistant, 'model answer'),
        ],
      );

      final results = await adapter.evaluate([item]);

      expect(results.total, 1);
      expect(results.allPassed, isTrue);
      expect(evaluator.lastMessages!.single.text, 'question');
      expect(evaluator.lastResponse!.text, 'model answer');
    });
  });

  group('AgentEvaluationExtensions', () {
    test('runs queries and evaluates responses', () async {
      final agent = _TestAgent();
      final evaluator = LocalEvaluator([EvalChecks.containsExpected()]);

      final results = await agent.evaluate(
        ['alpha', 'beta'],
        'eval',
        ['answer: alpha', 'answer: beta'],
        null,
        CancellationToken.none,
        evaluator: evaluator,
      );

      expect(agent.seenQueries, ['alpha', 'beta']);
      expect(results.allPassed, isTrue);
      expect(results.inputItems!.map((i) => i.query), ['alpha', 'beta']);
    });

    test('uses provided responses and validates counts', () async {
      final agent = _TestAgent();
      final evaluator = LocalEvaluator([EvalChecks.nonEmpty()]);
      final responses = [
        AgentResponse(
          message: ChatMessage.fromText(ChatRole.assistant, 'provided'),
        ),
      ];

      final results = await agent.evaluate(
        ['alpha'],
        'eval',
        null,
        null,
        CancellationToken.none,
        evaluator: evaluator,
        responses: responses,
      );

      expect(agent.seenQueries, isEmpty);
      expect(results.allPassed, isTrue);
      expect(
        () => agent.evaluate(
          ['alpha', 'beta'],
          'eval',
          null,
          null,
          CancellationToken.none,
          evaluator: evaluator,
          responses: responses,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Eval result data classes', () {
    test('score and per-evaluator equality plus item status helpers', () {
      expect(
        EvalScoreResult('quality', 1, passed: true),
        EvalScoreResult('quality', 1, passed: true),
      );
      expect(const PerEvaluatorResult(1, 2), const PerEvaluatorResult(1, 2));

      final item = EvalItemResult('item-1', 'pass', [
        EvalScoreResult('quality', 1, passed: true),
      ]);
      expect(item.isPassed, isTrue);
      expect(item.isFailed, isFalse);
      expect(item.isError, isFalse);
    });
  });
}

class _FakeEvaluator implements Evaluator {
  Iterable<ChatMessage>? lastMessages;
  ChatResponse? lastResponse;

  @override
  List<String> get evaluationMetricNames => ['fake'];

  @override
  Future<EvaluationResult> evaluate(
    Iterable<ChatMessage> messages,
    ChatResponse modelResponse, {
    ChatConfiguration? chatConfiguration,
    Iterable<EvaluationContext>? additionalContext,
    CancellationToken? cancellationToken,
  }) async {
    lastMessages = messages.toList();
    lastResponse = modelResponse;
    return EvaluationResult(
      metrics: {'fake': BooleanMetric('fake', value: true)},
    );
  }
}

class _FakeChatClient implements ChatClient {
  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    return ChatResponse.fromMessage(
      ChatMessage.fromText(ChatRole.assistant, 'unused'),
    );
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {}

  @override
  T? getService<T>({Object? key}) => null;

  @override
  void dispose() {}
}

class _TestAgent extends AIAgent {
  final List<String> seenQueries = [];

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<AgentSession> deserializeSessionCore(
    serializedState, {
    JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final query = messages.last.text;
    seenQueries.add(query);
    return AgentResponse(
      message: ChatMessage.fromText(ChatRole.assistant, 'answer: $query'),
    );
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {}

  @override
  Future serializeSessionCore(
    AgentSession session, {
    JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => {};
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}

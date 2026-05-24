import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/ai/ai_agent_builder.dart';
import 'package:agents/src/ai/harness/tool_approval/always_approve_tool_approval_response_content.dart';
import 'package:agents/src/ai/harness/tool_approval/tool_approval_agent.dart';
import 'package:agents/src/ai/harness/tool_approval/tool_approval_agent_builder_extensions.dart';
import 'package:agents/src/ai/harness/tool_approval/tool_approval_request_content_extensions.dart';
import 'package:agents/src/ai/harness/tool_approval/tool_approval_rule.dart';
import 'package:agents/src/ai/harness/tool_approval/tool_approval_state.dart';
import 'package:agents/src/json_stubs.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('ToolApprovalAgent', () {
    test(
      'constructor validates inner agent and accepts serializer options',
      () {
        expect(() => ToolApprovalAgent(null), throwsA(isA<ArgumentError>()));

        final innerAgent = _ScriptedAgent();
        final options = JsonSerializerOptions();
        final agent = ToolApprovalAgent(
          innerAgent,
          jsonSerializerOptions: options,
        );

        expect(agent.innerAgent, same(innerAgent));
      },
    );

    test('builder extension adds middleware', () {
      final innerAgent = _ScriptedAgent();

      final agent = AIAgentBuilder(
        innerAgent: innerAgent,
      ).useToolApproval().build();

      expect(agent, isA<ToolApprovalAgent>());
    });

    test('passes through when no approval requests exist', () async {
      final innerAgent = _ScriptedAgent()
        ..responses.add(_responseText('hello'));
      final agent = ToolApprovalAgent(innerAgent);

      final response = await agent.runCore([_userText('go')]);

      expect(response.text, 'hello');
      expect(innerAgent.runCount, 1);
      expect(innerAgent.capturedRuns.single.single.text, 'go');
    });

    test('surfaces unapproved request', () async {
      final request = _approvalRequest('r1', 'Search');
      final innerAgent = _ScriptedAgent()
        ..responses.add(_responseContents([request]));
      final agent = ToolApprovalAgent(innerAgent);

      final response = await agent.runCore([_userText('go')]);

      expect(_contentsOf<ToolApprovalRequestContent>(response), [request]);
      expect(innerAgent.runCount, 1);
    });

    test('auto-approves tool-level rule and reinvokes inner agent', () async {
      final request = _approvalRequest('r1', 'Search');
      final innerAgent = _ScriptedAgent()
        ..responses.addAll([
          _responseText('setup'),
          _responseContents([request]),
          _responseText('done'),
        ]);
      final agent = ToolApprovalAgent(innerAgent);
      final session = _TestSession();

      await agent.runCore([
        ChatMessage(
          role: ChatRole.user,
          contents: [request.createAlwaysApproveToolResponse()],
        ),
      ], session: session);
      final response = await agent.runCore([
        _userText('again'),
      ], session: session);

      expect(response.text, 'done');
      expect(innerAgent.runCount, 3);
      expect(
        innerAgent.capturedRuns.last.first.contents,
        contains(isA<ToolApprovalResponseContent>()),
      );
    });

    test('auto-approves matching arguments only for argument rule', () async {
      final request = _approvalRequest(
        'r1',
        'Search',
        arguments: {'query': 'dart'},
      );
      final mismatch = _approvalRequest(
        'r2',
        'Search',
        arguments: {'query': 'csharp'},
      );
      final innerAgent = _ScriptedAgent()
        ..responses.addAll([
          _responseText('setup'),
          _responseContents([mismatch]),
          _responseContents([request]),
          _responseText('matched'),
        ]);
      final agent = ToolApprovalAgent(innerAgent);
      final session = _TestSession();

      await agent.runCore([
        ChatMessage(
          role: ChatRole.user,
          contents: [request.createAlwaysApproveToolWithArgumentsResponse()],
        ),
      ], session: session);
      final first = await agent.runCore([
        _userText('mismatch'),
      ], session: session);
      final second = await agent.runCore([
        _userText('match'),
      ], session: session);

      expect(_contentsOf<ToolApprovalRequestContent>(first), [mismatch]);
      expect(second.text, 'matched');
    });

    test(
      'mixed auto-approved and unapproved requests are filtered and queued',
      () async {
        final auto = _approvalRequest('r1', 'AutoTool');
        final manual = _approvalRequest('r2', 'ManualTool');
        final innerAgent = _ScriptedAgent()
          ..responses.addAll([
            _responseText('setup'),
            _responseContents([
              TextContent('before'),
              auto,
              manual,
              TextContent('after'),
            ]),
          ]);
        final agent = ToolApprovalAgent(innerAgent);
        final session = _TestSession();

        await agent.runCore([
          ChatMessage(
            role: ChatRole.user,
            contents: [auto.createAlwaysApproveToolResponse()],
          ),
        ], session: session);
        final response = await agent.runCore([
          _userText('go'),
        ], session: session);

        expect(response.text, 'beforeafter');
        expect(_contentsOf<ToolApprovalRequestContent>(response), [manual]);
      },
    );

    test('always-approve unwraps and preserves content order', () async {
      final request = _approvalRequest('r1', 'Tool');
      final state = ToolApprovalState();

      final messages = ToolApprovalAgent.unwrapAlwaysApproveResponses(
        [
          ChatMessage(
            role: ChatRole.user,
            contents: [
              TextContent('a'),
              request.createAlwaysApproveToolResponse(reason: 'yes'),
              TextContent('b'),
            ],
          ),
        ],
        state,
        JsonSerializerOptions(),
      );

      final contents = messages.single.contents;
      expect(contents[0], isA<TextContent>());
      expect(contents[1], isA<ToolApprovalResponseContent>());
      expect(contents[2], isA<TextContent>());
      expect(
        contents,
        isNot(contains(isA<AlwaysApproveToolApprovalResponseContent>())),
      );
      expect(state.rules, hasLength(1));
    });

    test('rules persist and duplicate rules are not added', () async {
      final request = _approvalRequest('r1', 'Tool');
      final agent = ToolApprovalAgent(
        _ScriptedAgent()..responses.add(_responseText('ok')),
      );
      final session = _TestSession();

      for (var i = 0; i < 2; i++) {
        await agent.runCore([
          ChatMessage(
            role: ChatRole.user,
            contents: [request.createAlwaysApproveToolResponse()],
          ),
        ], session: session);
      }

      final state = session.stateBag.getValue<ToolApprovalState>(
        'toolApprovalState',
      );
      expect(state!.rules, hasLength(1));
      expect(state.rules.single.toolName, 'Tool');
    });

    test('collected responses are injected once and then cleared', () async {
      final first = _approvalRequest('r1', 'First');
      final second = _approvalRequest('r2', 'Second');
      final innerAgent = _ScriptedAgent()
        ..responses.addAll([
          _responseContents([first, second]),
          _responseText('after approvals'),
          _responseText('later'),
        ]);
      final agent = ToolApprovalAgent(innerAgent);
      final session = _TestSession();

      final initial = await agent.runCore([
        _userText('start'),
      ], session: session);
      expect(_contentsOf<ToolApprovalRequestContent>(initial), [first]);

      final queued = await agent.runCore([
        ChatMessage(
          role: ChatRole.user,
          contents: [first.createResponse(true)],
        ),
      ], session: session);
      expect(_contentsOf<ToolApprovalRequestContent>(queued), [second]);

      await agent.runCore([
        ChatMessage(
          role: ChatRole.user,
          contents: [second.createResponse(false, reason: 'no')],
        ),
      ], session: session);
      await agent.runCore([_userText('later')], session: session);

      final injected = innerAgent.capturedRuns[1].first.contents
          .whereType<ToolApprovalResponseContent>()
          .toList();
      expect(injected, hasLength(2));
      expect(
        innerAgent.capturedRuns[2].first.contents,
        isNot(contains(isA<ToolApprovalResponseContent>())),
      );
    });

    test(
      'queued requests can be resolved by always-approve response',
      () async {
        final first = _approvalRequest('r1', 'Manual');
        final second = _approvalRequest('r2', 'AutoLater');
        final innerAgent = _ScriptedAgent()
          ..responses.addAll([
            _responseContents([first, second]),
            _responseText('done'),
          ]);
        final agent = ToolApprovalAgent(innerAgent);
        final session = _TestSession();

        await agent.runCore([_userText('start')], session: session);
        final response = await agent.runCore([
          ChatMessage(
            role: ChatRole.user,
            contents: [first.createAlwaysApproveToolResponse()],
          ),
        ], session: session);

        expect(_contentsOf<ToolApprovalRequestContent>(response), [second]);
        await agent.runCore([
          ChatMessage(
            role: ChatRole.user,
            contents: [second.createAlwaysApproveToolResponse()],
          ),
        ], session: session);
        expect(innerAgent.runCount, 2);
        expect(
          innerAgent.capturedRuns.last.first.contents
              .whereType<ToolApprovalResponseContent>(),
          hasLength(2),
        );
      },
    );

    test('streaming passes through when no approval requests exist', () async {
      final innerAgent = _ScriptedAgent()
        ..streamResponses.add([
          AgentResponseUpdate(role: ChatRole.assistant, content: 'hello'),
        ]);
      final agent = ToolApprovalAgent(innerAgent);

      final updates = await agent.runCoreStreaming([_userText('go')]).toList();

      expect(updates.single.text, 'hello');
    });

    test('streaming removes auto-approved requests and reinvokes', () async {
      final request = _approvalRequest('r1', 'Tool');
      final innerAgent = _ScriptedAgent()
        ..streamResponses.addAll([
          [
            AgentResponseUpdate(
              role: ChatRole.assistant,
              contents: [TextContent('visible'), request],
            ),
          ],
          [AgentResponseUpdate(role: ChatRole.assistant, content: 'done')],
        ]);
      final agent = ToolApprovalAgent(innerAgent);
      final session = _TestSession();

      await agent.runCore([
        ChatMessage(
          role: ChatRole.user,
          contents: [request.createAlwaysApproveToolResponse()],
        ),
      ], session: session);
      final updates = await agent.runCoreStreaming([
        _userText('go'),
      ], session: session).toList();

      expect(updates.map((u) => u.text).join(), 'visibledone');
      expect(
        updates.expand((u) => u.contents),
        isNot(contains(isA<ToolApprovalRequestContent>())),
      );
      expect(innerAgent.streamCount, 2);
    });

    test('streaming surfaces nonmatching and queues excess requests', () async {
      final first = _approvalRequest('r1', 'First');
      final second = _approvalRequest('r2', 'Second');
      final innerAgent = _ScriptedAgent()
        ..streamResponses.add([
          AgentResponseUpdate(
            role: ChatRole.assistant,
            contents: [first, second],
          ),
        ]);
      final agent = ToolApprovalAgent(innerAgent);
      final session = _TestSession();

      final updates = await agent.runCoreStreaming([
        _userText('go'),
      ], session: session).toList();
      final queued = await agent.runCoreStreaming([
        ChatMessage(
          role: ChatRole.user,
          contents: [first.createResponse(true)],
        ),
      ], session: session).toList();

      expect(_updateContentsOf<ToolApprovalRequestContent>(updates), [first]);
      expect(_updateContentsOf<ToolApprovalRequestContent>(queued), [second]);
      expect(innerAgent.streamCount, 1);
    });

    test(
      'streaming mixed update yields normal content and first unapproved',
      () async {
        final auto = _approvalRequest('r1', 'Auto');
        final manual = _approvalRequest('r2', 'Manual');
        final innerAgent = _ScriptedAgent()
          ..streamResponses.add([
            AgentResponseUpdate(
              role: ChatRole.assistant,
              contents: [TextContent('keep'), auto, manual],
            ),
          ]);
        final agent = ToolApprovalAgent(innerAgent);
        final session = _TestSession();

        await agent.runCore([
          ChatMessage(
            role: ChatRole.user,
            contents: [auto.createAlwaysApproveToolResponse()],
          ),
        ], session: session);
        final updates = await agent.runCoreStreaming([
          _userText('go'),
        ], session: session).toList();

        expect(updates.first.text, 'keep');
        expect(_updateContentsOf<ToolApprovalRequestContent>(updates), [
          manual,
        ]);
      },
    );

    test('matchesRule handles tool names and exact argument serialization', () {
      final request = _approvalRequest(
        'r1',
        'Tool',
        arguments: {
          'text': 'abc',
          'count': 2,
          'json': const JsonElement({'x': true}),
        },
      );
      final arguments = ToolApprovalAgent.serializeArguments({
        'text': 'abc',
        'count': 2,
        'json': const JsonElement({'x': true}),
      }, JsonSerializerOptions());

      expect(
        ToolApprovalAgent.matchesRule(request, [
          ToolApprovalRule(toolName: 'Tool'),
        ], JsonSerializerOptions()),
        isTrue,
      );
      expect(
        ToolApprovalAgent.matchesRule(request, [
          ToolApprovalRule(toolName: 'Tool', arguments: arguments),
        ], JsonSerializerOptions()),
        isTrue,
      );
      expect(
        ToolApprovalAgent.matchesRule(request, [
          ToolApprovalRule(
            toolName: 'Tool',
            arguments: {'text': '"different"'},
          ),
        ], JsonSerializerOptions()),
        isFalse,
      );
    });

    test('non-function tool calls do not match rules', () {
      final request = ToolApprovalRequestContent(
        requestId: 'r1',
        toolCall: _OtherToolCall('c1'),
      );

      expect(
        ToolApprovalAgent.matchesRule(request, [
          ToolApprovalRule(toolName: 'Tool'),
        ], JsonSerializerOptions()),
        isFalse,
      );
    });

    test('extension methods set flags and wrap approved responses', () {
      final request = _approvalRequest('r1', 'Tool');

      final tool = request.createAlwaysApproveToolResponse(reason: 'ok');
      final withArguments = request
          .createAlwaysApproveToolWithArgumentsResponse(reason: 'ok');

      expect(tool.alwaysApproveTool, isTrue);
      expect(tool.alwaysApproveToolWithArguments, isFalse);
      expect(tool.innerResponse.approved, isTrue);
      expect(tool.innerResponse.reason, 'ok');
      expect(withArguments.alwaysApproveTool, isFalse);
      expect(withArguments.alwaysApproveToolWithArguments, isTrue);
    });

    test('always approve content validates inner response', () {
      expect(
        () => AlwaysApproveToolApprovalResponseContent(null, true, false),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

class _ScriptedAgent extends AIAgent {
  final List<AgentResponse> responses = [];
  final List<List<AgentResponseUpdate>> streamResponses = [];
  final List<List<ChatMessage>> capturedRuns = [];
  final List<List<ChatMessage>> capturedStreams = [];

  int runCount = 0;
  int streamCount = 0;

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async {
    return _TestSession();
  }

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async {
    return _TestSession();
  }

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    capturedRuns.add(List<ChatMessage>.of(messages));
    runCount++;
    if (responses.isEmpty) {
      return _responseText('ok');
    }
    return responses.removeAt(0);
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    capturedStreams.add(List<ChatMessage>.of(messages));
    streamCount++;
    final updates = streamResponses.isEmpty
        ? <AgentResponseUpdate>[]
        : streamResponses.removeAt(0);
    for (final update in updates) {
      yield update;
    }
  }

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async {
    return null;
  }
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}

class _FunctionToolCall extends ToolCallContent implements FunctionCallContent {
  _FunctionToolCall({
    required super.callId,
    required this.name,
    this.arguments,
  });

  @override
  final String name;

  @override
  final Map<String, Object?>? arguments;

  @override
  Exception? exception;
}

class _OtherToolCall extends ToolCallContent {
  _OtherToolCall(String callId) : super(callId: callId);
}

ChatMessage _userText(String text) => ChatMessage.fromText(ChatRole.user, text);

AgentResponse _responseText(String text) {
  return AgentResponse(message: ChatMessage.fromText(ChatRole.assistant, text));
}

AgentResponse _responseContents(List<AIContent> contents) {
  return AgentResponse(
    message: ChatMessage(role: ChatRole.assistant, contents: contents),
  );
}

ToolApprovalRequestContent _approvalRequest(
  String requestId,
  String toolName, {
  Map<String, Object?>? arguments,
}) {
  return ToolApprovalRequestContent(
    requestId: requestId,
    toolCall: _FunctionToolCall(
      callId: 'call-$requestId',
      name: toolName,
      arguments: arguments,
    ),
  );
}

List<T> _contentsOf<T extends AIContent>(AgentResponse response) {
  return response.messages
      .expand((message) => message.contents)
      .whereType<T>()
      .toList();
}

List<T> _updateContentsOf<T extends AIContent>(
  List<AgentResponseUpdate> updates,
) {
  return updates.expand((update) => update.contents).whereType<T>().toList();
}

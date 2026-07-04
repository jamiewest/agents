// ignore_for_file: non_constant_identifier_names
import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_context.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/ai/chat_client/message_injecting_chat_client.dart';
import 'package:agents/src/ai/chat_client/non_approval_required_function_bypassing_chat_client.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  late _TestSession session;

  setUp(() {
    session = _TestSession();
    AIAgent.currentRunContext = AgentRunContext(
      _StubAgent(),
      session,
      <ChatMessage>[],
      null,
    );
  });

  tearDown(() => AIAgent.currentRunContext = null);

  group('MessageInjectingChatClient', () {
    test('throws without a run context', () async {
      AIAgent.currentRunContext = null;
      final client = MessageInjectingChatClient(_ScriptedChatClient());

      await expectLater(
        () => client.getResponse(
          messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
        ),
        throwsStateError,
      );
    });

    test('passes through when no messages are injected', () async {
      final inner = _ScriptedChatClient()
        ..responses.add(_textResponse('reply'));
      final client = MessageInjectingChatClient(inner);

      final response = await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
      );

      expect(response.text, 'reply');
      expect(inner.calls, hasLength(1));
    });

    test('drains queued messages into the request', () async {
      final inner = _ScriptedChatClient()
        ..responses.add(_textResponse('reply'));
      final client = MessageInjectingChatClient(inner);
      client.enqueueMessages(session, [
        ChatMessage.fromText(ChatRole.user, 'injected'),
      ]);

      await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
      );

      expect(inner.calls.single.map((m) => m.text), ['hi', 'injected']);
      expect(client.getPendingMessages(session), isEmpty);
    });

    test('loops when messages are injected during the call', () async {
      late MessageInjectingChatClient client;
      final inner = _ScriptedChatClient();
      client = MessageInjectingChatClient(inner);
      inner.onCall = (messages) {
        if (inner.calls.length == 1) {
          client.enqueueMessages(session, [
            ChatMessage.fromText(ChatRole.user, 'follow-up'),
          ]);
          return _textResponse('first');
        }
        return _textResponse('second');
      };

      final response = await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
      );

      expect(response.text, 'second');
      expect(inner.calls, hasLength(2));
      expect(inner.calls.last.map((m) => m.text), ['follow-up']);
    });

    test('returns immediately when response has function calls', () async {
      late MessageInjectingChatClient client;
      final inner = _ScriptedChatClient();
      client = MessageInjectingChatClient(inner);
      inner.onCall = (messages) {
        client.enqueueMessages(session, [
          ChatMessage.fromText(ChatRole.user, 'pending'),
        ]);
        return ChatResponse.fromMessage(
          ChatMessage(
            role: ChatRole.assistant,
            contents: [FunctionCallContent(callId: 'c1', name: 'tool')],
          ),
        );
      };

      await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
      );

      expect(inner.calls, hasLength(1));
      expect(client.getPendingMessages(session), hasLength(1));
    });
  });

  group('NonApprovalRequiredFunctionBypassingChatClient', () {
    test('strips approval requests for non-approval-required tools', () async {
      final freeTool = _tool('free_tool');
      final guardedTool = ApprovalRequiredAIFunction(_tool('guarded_tool'));
      final freeApproval = _approvalRequest('a1', 'free_tool');
      final guardedApproval = _approvalRequest('a2', 'guarded_tool');
      final inner = _ScriptedChatClient()
        ..responses.add(
          ChatResponse.fromMessage(
            ChatMessage(
              role: ChatRole.assistant,
              contents: [freeApproval, guardedApproval],
            ),
          ),
        );
      final client = NonApprovalRequiredFunctionBypassingChatClient(inner);

      final response = await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
        options: ChatOptions(tools: [freeTool, guardedTool]),
      );

      final remaining = response.messages
          .expand((m) => m.contents)
          .whereType<ToolApprovalRequestContent>()
          .toList();
      expect(remaining, [guardedApproval]);
    });

    test('re-injects stored auto-approvals as approved on next call', () async {
      final freeTool = _tool('free_tool');
      final freeApproval = _approvalRequest('a1', 'free_tool');
      final inner = _ScriptedChatClient()
        ..responses.addAll([
          ChatResponse.fromMessage(
            ChatMessage(role: ChatRole.assistant, contents: [freeApproval]),
          ),
          _textResponse('done'),
        ]);
      final client = NonApprovalRequiredFunctionBypassingChatClient(inner);
      final options = ChatOptions(tools: [freeTool]);

      final first = await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
        options: options,
      );
      expect(
        first.messages.expand((m) => m.contents),
        isNot(contains(isA<ToolApprovalRequestContent>())),
      );

      await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'next')],
        options: options,
      );

      final injected = inner.calls.last
          .expand((m) => m.contents)
          .whereType<ToolApprovalResponseContent>()
          .toList();
      expect(injected, hasLength(1));
      expect(injected.single.approved, isTrue);
    });

    test('unknown tools are treated as approval-required', () async {
      final approval = _approvalRequest('a1', 'unknown_tool');
      final inner = _ScriptedChatClient()
        ..responses.add(
          ChatResponse.fromMessage(
            ChatMessage(role: ChatRole.assistant, contents: [approval]),
          ),
        );
      final client = NonApprovalRequiredFunctionBypassingChatClient(inner);

      final response = await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
      );

      expect(response.messages.expand((m) => m.contents), contains(approval));
    });
  });
}

ChatResponse _textResponse(String text) =>
    ChatResponse.fromMessage(ChatMessage.fromText(ChatRole.assistant, text));

AIFunction _tool(String name) => AIFunctionFactory.create(
  name: name,
  description: name,
  parametersSchema: const {'type': 'object', 'properties': <String, Object?>{}},
  callback: (arguments, {cancellationToken}) async => 'ok',
);

class _ScriptedChatClient implements ChatClient {
  final List<ChatResponse> responses = [];
  final List<List<ChatMessage>> calls = [];
  ChatResponse Function(List<ChatMessage> messages)? onCall;

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final list = List<ChatMessage>.of(messages);
    calls.add(list);
    if (onCall != null) {
      return onCall!(list);
    }
    return responses.removeAt(0);
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final response = await getResponse(
      messages: messages,
      options: options,
      cancellationToken: cancellationToken,
    );
    for (final message in response.messages) {
      yield ChatResponseUpdate(
        role: message.role,
        contents: List<AIContent>.of(message.contents),
      );
    }
  }

  @override
  T? getService<T>({Object? key}) => null;

  @override
  void dispose() {}
}

ToolApprovalRequestContent _approvalRequest(String requestId, String name) =>
    ToolApprovalRequestContent(
      requestId: requestId,
      toolCall: _FunctionToolCall(callId: 'call-$requestId', name: name),
    );

class _FunctionToolCall extends ToolCallContent implements FunctionCallContent {
  _FunctionToolCall({required super.callId, required this.name});

  @override
  final String name;

  @override
  Map<String, Object?>? arguments;

  @override
  Exception? exception;
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}

class _StubAgent extends AIAgent {
  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => {};

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async =>
      AgentResponse(message: ChatMessage.fromText(ChatRole.assistant, 'ok'));

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {}
}

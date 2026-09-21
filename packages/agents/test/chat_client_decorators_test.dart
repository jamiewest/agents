import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_context.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/ai/chat_client/message_injecting_chat_client.dart';
import 'package:agents/src/ai/chat_client/approval_not_required_function_bypassing_chat_client.dart';
import 'package:agents/src/ai/chat_client/approval_response_binding_chat_client.dart';
import 'package:agents/src/ai/chat_client/chat_client_agent.dart';
import 'package:agents/src/ai/chat_client/chat_client_agent_options.dart';
import 'package:agents/src/ai/chat_client/chat_client_extensions.dart';
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

  group('ApprovalNotRequiredFunctionBypassingChatClient', () {
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
      final client = ApprovalNotRequiredFunctionBypassingChatClient(inner);

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
      final client = ApprovalNotRequiredFunctionBypassingChatClient(inner);
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

    test('streams through unchanged without a session', () async {
      AIAgent.currentRunContext = null;
      final freeTool = _tool('free_tool');
      final approval = _approvalRequest('a1', 'free_tool');
      final inner = _ScriptedChatClient()
        ..responses.add(
          ChatResponse.fromMessage(
            ChatMessage(role: ChatRole.assistant, contents: [approval]),
          ),
        );
      final client = ApprovalNotRequiredFunctionBypassingChatClient(inner);

      final updates = await client
          .getStreamingResponse(
            messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
            options: ChatOptions(tools: [freeTool]),
          )
          .toList();

      // With no session there is nowhere to stash the request, so it must
      // reach the caller rather than being silently swallowed.
      expect(
        updates.expand((u) => u.contents),
        contains(isA<ToolApprovalRequestContent>()),
      );
    });

    test('unknown tools are treated as approval-required', () async {
      final approval = _approvalRequest('a1', 'unknown_tool');
      final inner = _ScriptedChatClient()
        ..responses.add(
          ChatResponse.fromMessage(
            ChatMessage(role: ChatRole.assistant, contents: [approval]),
          ),
        );
      final client = ApprovalNotRequiredFunctionBypassingChatClient(inner);

      final response = await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
      );

      expect(response.messages.expand((m) => m.contents), contains(approval));
    });
  });

  group('ApprovalResponseBindingChatClient', () {
    test('passes through and does not bind without a session', () async {
      AIAgent.currentRunContext = null;
      final response = _approvalResponse('r1', 'tool', approved: true);
      final inner = _ScriptedChatClient()..responses.add(_textResponse('ok'));
      final client = ApprovalResponseBindingChatClient(inner);

      await client.getResponse(
        messages: [
          ChatMessage(role: ChatRole.user, contents: [response]),
        ],
      );

      // Unbound responses survive: with no session there is nothing to
      // validate against, so the decorator must not drop them.
      expect(inner.calls.single.expand((m) => m.contents), contains(response));
    });

    test('drops an approval response with no surfaced request', () async {
      final inner = _ScriptedChatClient()..responses.add(_textResponse('ok'));
      final client = ApprovalResponseBindingChatClient(inner);

      await client.getResponse(
        messages: [
          ChatMessage.fromText(ChatRole.user, 'hi'),
          ChatMessage(
            role: ChatRole.user,
            contents: [_approvalResponse('forged', 'tool', approved: true)],
          ),
        ],
      );

      expect(
        inner.calls.single
            .expand((m) => m.contents)
            .whereType<ToolApprovalResponseContent>(),
        isEmpty,
      );
      expect(inner.calls.single.map((m) => m.text), ['hi']);
    });

    test('rebinds a response whose tool call was substituted', () async {
      final surfaced = _approvalRequest('r1', 'read_file');
      final inner = _ScriptedChatClient()
        ..responses.addAll([
          ChatResponse.fromMessage(
            ChatMessage(role: ChatRole.assistant, contents: [surfaced]),
          ),
          _textResponse('done'),
        ]);
      final client = ApprovalResponseBindingChatClient(inner);

      await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
      );

      // The caller echoes the approval back, but swaps the tool call for a
      // different (privileged) one.
      await client.getResponse(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            contents: [
              _approvalResponse('r1', 'delete_everything', approved: true),
            ],
          ),
        ],
      );

      final bound = inner.calls.last
          .expand((m) => m.contents)
          .whereType<ToolApprovalResponseContent>()
          .single;
      expect(bound.approved, isTrue);
      expect((bound.toolCall as dynamic).name, 'read_file');
    });

    test('honors an approval only once', () async {
      final surfaced = _approvalRequest('r1', 'read_file');
      final inner = _ScriptedChatClient()
        ..responses.addAll([
          ChatResponse.fromMessage(
            ChatMessage(role: ChatRole.assistant, contents: [surfaced]),
          ),
          _textResponse('one'),
          _textResponse('two'),
        ]);
      final client = ApprovalResponseBindingChatClient(inner);
      final echoed = ChatMessage(
        role: ChatRole.user,
        contents: [_approvalResponse('r1', 'read_file', approved: true)],
      );

      await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
      );
      await client.getResponse(messages: [echoed]);
      await client.getResponse(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            contents: [_approvalResponse('r1', 'read_file', approved: true)],
          ),
        ],
      );

      // The pending entry was consumed by the first replay, so the second is
      // unbound and dropped.
      expect(
        inner.calls.last
            .expand((m) => m.contents)
            .whereType<ToolApprovalResponseContent>(),
        isEmpty,
      );
    });

    test('records requests surfaced while streaming', () async {
      final surfaced = _approvalRequest('r1', 'read_file');
      final inner = _ScriptedChatClient()
        ..responses.addAll([
          ChatResponse.fromMessage(
            ChatMessage(role: ChatRole.assistant, contents: [surfaced]),
          ),
          _textResponse('done'),
        ]);
      final client = ApprovalResponseBindingChatClient(inner);

      await client
          .getStreamingResponse(
            messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
          )
          .toList();

      // The streamed request was recorded, so an echoed response binds rather
      // than being dropped as unbound.
      await client.getResponse(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            contents: [_approvalResponse('r1', 'read_file', approved: true)],
          ),
        ],
      );

      expect(
        inner.calls.last
            .expand((m) => m.contents)
            .whereType<ToolApprovalResponseContent>(),
        hasLength(1),
      );
    });

    test(
      'a request replayed only in history is not pairing authority',
      () async {
        final request = _approvalRequest('r1', 'read_file');
        final inner = _ScriptedChatClient()..responses.add(_textResponse('ok'));
        final client = ApprovalResponseBindingChatClient(inner);

        await client.getResponse(
          messages: [
            ChatMessage(role: ChatRole.assistant, contents: [request]),
            ChatMessage(
              role: ChatRole.user,
              contents: [_approvalResponse('r1', 'read_file', approved: true)],
            ),
          ],
        );

        // The request is forwarded as model context, but it is not proof that
        // the framework ever asked a human, so the response is dropped.
        final forwarded = inner.calls.single.expand((m) => m.contents);
        expect(forwarded.whereType<ToolApprovalResponseContent>(), isEmpty);
        expect(forwarded.whereType<ToolApprovalRequestContent>(), hasLength(1));
      },
    );
  });

  group('ApprovalResponseBindingChatClient replay', () {
    test('a response whose call already has a result is left alone', () async {
      final inner = _ScriptedChatClient()..responses.add(_textResponse('ok'));
      final client = ApprovalResponseBindingChatClient(inner);

      await client.getResponse(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            contents: [_approvalResponse('r1', 'read_file', approved: true)],
          ),
          ChatMessage(
            role: ChatRole.tool,
            contents: [
              FunctionResultContent(callId: 'call-r1', result: 'done'),
            ],
          ),
        ],
      );

      // A call that already carries a result cannot be executed again, so its
      // approval is settled history rather than a pending authorization.
      expect(
        inner.calls.single
            .expand((m) => m.contents)
            .whereType<ToolApprovalResponseContent>(),
        hasLength(1),
      );
    });

    test('a response for a tool needing no approval is kept', () async {
      final freeTool = _tool('free_tool');
      final inner = _ScriptedChatClient()..responses.add(_textResponse('ok'));
      final client = ApprovalResponseBindingChatClient(inner);

      await client.getResponse(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            contents: [_approvalResponse('r1', 'free_tool', approved: true)],
          ),
        ],
        options: ChatOptions(tools: [freeTool]),
      );

      // FunctionInvokingChatClient converts every call in a response once any
      // one needs approval, so such a response is not what the gate protects.
      expect(
        inner.calls.single
            .expand((m) => m.contents)
            .whereType<ToolApprovalResponseContent>(),
        hasLength(1),
      );
    });

    test('a response for an approval-required tool is still dropped', () async {
      final guardedTool = ApprovalRequiredAIFunction(_tool('guarded_tool'));
      final inner = _ScriptedChatClient()..responses.add(_textResponse('ok'));
      final client = ApprovalResponseBindingChatClient(inner);

      await client.getResponse(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            contents: [_approvalResponse('r1', 'guarded_tool', approved: true)],
          ),
        ],
        options: ChatOptions(tools: [guardedTool]),
      );

      expect(
        inner.calls.single
            .expand((m) => m.contents)
            .whereType<ToolApprovalResponseContent>(),
        isEmpty,
      );
    });
  });

  group('default agent middleware', () {
    test('nests binding above bypassing above function invocation', () {
      final pipeline = _ScriptedChatClient().withDefaultAgentMiddleware();

      final nesting = <Type>[];
      ChatClient current = pipeline;
      while (current is DelegatingChatClient) {
        nesting.add(current.runtimeType);
        current = current.innerClient;
      }

      expect(nesting, [
        ApprovalResponseBindingChatClient,
        ApprovalNotRequiredFunctionBypassingChatClient,
        FunctionInvokingChatClient,
      ]);
    });

    test('each decorator can be disabled', () {
      final pipeline = _ScriptedChatClient().withDefaultAgentMiddleware(
        options: ChatClientAgentOptions()
          ..disableApprovalResponseBinding = true
          ..disableApprovalNotRequiredFunctionBypassing = true,
      );

      expect(pipeline, isA<FunctionInvokingChatClient>());
    });

    test(
      'binding does not drop the synthetic auto-approval injected below it',
      () async {
        final freeTool = _tool('free_tool');
        final approval = _approvalRequest('a1', 'free_tool');
        final leaf = _ScriptedChatClient()
          ..responses.addAll([
            ChatResponse.fromMessage(
              ChatMessage(role: ChatRole.assistant, contents: [approval]),
            ),
            _textResponse('done'),
          ]);
        final pipeline = leaf.withDefaultAgentMiddleware();
        final options = ChatOptions(tools: [freeTool]);

        await pipeline.getResponse(
          messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
          options: options,
        );
        await pipeline.getResponse(
          messages: [ChatMessage.fromText(ChatRole.user, 'next')],
          options: options,
        );

        // The bypassing client stashed the request and re-injects it as an
        // approved response on the next turn. That response is synthetic and
        // has no request recorded by the binding client, so it survives only
        // because the injection happens *below* the binding client.
        final injected = leaf.calls.last
            .expand((m) => m.contents)
            .whereType<ToolApprovalResponseContent>()
            .toList();
        expect(injected, hasLength(1));
        expect(injected.single.approved, isTrue);
      },
    );

    test('ChatClientAgent nests the decorators in the same order', () {
      // ChatClientAgent builds its own pipeline (it also installs message
      // injection), so assert on the agent's real chat client rather than
      // trusting the withDefaultAgentMiddleware extension to stand in for it.
      final agent = ChatClientAgent(_ScriptedChatClient());

      final nesting = <Type>[];
      ChatClient current = agent.chatClient;
      while (current is DelegatingChatClient) {
        nesting.add(current.runtimeType);
        current = current.innerClient;
      }

      expect(nesting.take(3), [
        ApprovalResponseBindingChatClient,
        ApprovalNotRequiredFunctionBypassingChatClient,
        FunctionInvokingChatClient,
      ]);
    });

    test(
      'a ChatClientAgent run carries the auto-approval through to the client',
      () async {
        final freeTool = _tool('free_tool');
        final approval = _approvalRequest('a1', 'free_tool');
        final leaf = _ScriptedChatClient()
          ..responses.addAll([
            ChatResponse.fromMessage(
              ChatMessage(role: ChatRole.assistant, contents: [approval]),
            ),
            _textResponse('done'),
          ]);
        final agent = ChatClientAgent(
          leaf,
          options: ChatClientAgentOptions()
            ..chatOptions = (ChatOptions(tools: [freeTool])),
        );
        final agentSession = await agent.createSession();

        await agent.run(agentSession, null, messages: [_userText('hi')]);
        await agent.run(agentSession, null, messages: [_userText('next')]);

        final injected = leaf.calls.last
            .expand((m) => m.contents)
            .whereType<ToolApprovalResponseContent>()
            .toList();
        expect(injected, hasLength(1));
        expect(injected.single.approved, isTrue);
      },
    );
  });
}

ChatMessage _userText(String text) => ChatMessage.fromText(ChatRole.user, text);

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

ToolApprovalResponseContent _approvalResponse(
  String requestId,
  String name, {
  required bool approved,
}) => ToolApprovalResponseContent(
  requestId: requestId,
  approved: approved,
  toolCall: _FunctionToolCall(callId: 'call-$requestId', name: name),
);

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
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? jsonSerializerOptions,
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

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import 'package:agents/src/ai/microsoft_agents_ai/harness/agent_mode/agent_mode_provider.dart';
import 'package:agents/src/ai/microsoft_agents_ai/harness/agent_mode/agent_mode_provider_options.dart';
import 'package:agents/src/ai/microsoft_agents_ai/harness/agent_mode/agent_mode_state.dart';

void main() {
  group('AgentModeProvider context', () {
    test('returns tools and instructions', () async {
      final provider = AgentModeProvider();

      final result = await provider.invoking(createInvokingContext());

      expect(result.instructions, isNotNull);
      expect(result.tools, hasLength(2));
      expect(
        result.tools!.whereType<AIFunction>().map((t) => t.name),
        unorderedEquals(['AgentMode_Set', 'AgentMode_Get']),
      );
    });

    test('instructions include current mode', () async {
      final provider = AgentModeProvider();

      final result = await provider.invoking(createInvokingContext());

      expect(result.instructions, contains('plan'));
    });
  });

  group('AgentModeProvider tools', () {
    test('set mode changes mode', () async {
      final (tools, state, _) = await createToolsWithState();
      final setMode = getTool(tools, 'AgentMode_Set');

      await setMode.invoke(AIFunctionArguments({'mode': 'execute'}));

      expect(state.currentMode, 'execute');
    });

    test('set mode returns confirmation', () async {
      final (tools, _, _) = await createToolsWithState();
      final setMode = getTool(tools, 'AgentMode_Set');

      final result = await setMode.invoke(
        AIFunctionArguments({'mode': 'execute'}),
      );

      expect(result, 'Mode changed to "execute".');
    });

    test('set mode invalid mode throws and does not persist', () async {
      final (tools, _, _) = await createToolsWithState();
      final setMode = getTool(tools, 'AgentMode_Set');
      final getMode = getTool(tools, 'AgentMode_Get');

      await expectLater(
        setMode.invoke(AIFunctionArguments({'mode': 'foo'})),
        throwsArgumentError,
      );

      final currentMode = await getMode.invoke(AIFunctionArguments());
      expect(currentMode, 'plan');
    });

    test('get mode returns default mode', () async {
      final (tools, _, _) = await createToolsWithState();
      final getMode = getTool(tools, 'AgentMode_Get');

      final result = await getMode.invoke(AIFunctionArguments());

      expect(result, 'plan');
    });

    test('get mode returns updated mode after set', () async {
      final (tools, _, _) = await createToolsWithState();
      final setMode = getTool(tools, 'AgentMode_Set');
      final getMode = getTool(tools, 'AgentMode_Get');

      await setMode.invoke(AIFunctionArguments({'mode': 'execute'}));
      final result = await getMode.invoke(AIFunctionArguments());

      expect(result, 'execute');
    });
  });

  group('AgentModeProvider public helpers', () {
    test('get mode returns default mode', () {
      final provider = AgentModeProvider();
      final session = TestSession();

      final mode = provider.getMode(session);

      expect(mode, 'plan');
    });

    test('set mode changes mode', () {
      final provider = AgentModeProvider();
      final session = TestSession();

      provider.setMode(session, 'execute');
      final mode = provider.getMode(session);

      expect(mode, 'execute');
    });

    test('set mode invalid mode throws and does not persist', () {
      final provider = AgentModeProvider();
      final session = TestSession();

      expect(() => provider.setMode(session, 'foo'), throwsArgumentError);

      expect(provider.getMode(session), 'plan');
    });

    test('set mode reflected in tool results', () async {
      final provider = AgentModeProvider();
      final session = TestSession();
      provider.setMode(session, 'execute');

      final result = await provider.invoking(
        createInvokingContext(session: session),
      );
      final getMode = getTool(result.tools!, 'AgentMode_Get');
      final modeResult = await getMode.invoke(AIFunctionArguments());

      expect(modeResult, 'execute');
      expect(result.instructions, contains('execute'));
    });
  });

  group('AgentModeProvider state persistence', () {
    test('state persists across invocations', () async {
      final provider = AgentModeProvider();
      final session = TestSession();
      final context = createInvokingContext(session: session);

      final result1 = await provider.invoking(context);
      final setMode = getTool(result1.tools!, 'AgentMode_Set');
      await setMode.invoke(AIFunctionArguments({'mode': 'execute'}));

      final result2 = await provider.invoking(context);
      final getMode = getTool(result2.tools!, 'AgentMode_Get');
      final modeResult = await getMode.invoke(AIFunctionArguments());

      expect(modeResult, 'execute');
      expect(result2.instructions, contains('execute'));
    });
  });

  group('AgentModeProvider options', () {
    test('custom instructions override default', () async {
      final provider = AgentModeProvider(
        options: AgentModeProviderOptions()
          ..instructions = 'Custom mode instructions.',
      );

      final result = await provider.invoking(createInvokingContext());

      expect(result.instructions, 'Custom mode instructions.');
    });

    test('custom modes are used', () {
      final provider = AgentModeProvider(
        options: AgentModeProviderOptions()
          ..modes = [
            AgentMode('draft', 'Drafting mode.'),
            AgentMode('review', 'Review mode.'),
          ],
      );
      final session = TestSession();

      final mode = provider.getMode(session);

      expect(mode, 'draft');
    });

    test('custom modes set mode validates against list', () {
      final provider = AgentModeProvider(
        options: AgentModeProviderOptions()
          ..modes = [
            AgentMode('draft', 'Drafting mode.'),
            AgentMode('review', 'Review mode.'),
          ],
      );
      final session = TestSession();

      provider.setMode(session, 'review');

      expect(provider.getMode(session), 'review');
      expect(() => provider.setMode(session, 'plan'), throwsArgumentError);
    });

    test('custom default mode is used', () {
      final provider = AgentModeProvider(
        options: AgentModeProviderOptions()
          ..modes = [
            AgentMode('draft', 'Drafting mode.'),
            AgentMode('review', 'Review mode.'),
          ]
          ..defaultMode = 'review',
      );
      final session = TestSession();

      final mode = provider.getMode(session);

      expect(mode, 'review');
    });

    test('invalid default mode throws', () {
      final options = AgentModeProviderOptions()
        ..modes = [AgentMode('draft', 'Drafting mode.')]
        ..defaultMode = 'nonexistent';

      expect(() => AgentModeProvider(options: options), throwsArgumentError);
    });

    test('empty modes throws', () {
      final options = AgentModeProviderOptions()..modes = [];

      expect(() => AgentModeProvider(options: options), throwsArgumentError);
    });

    test('custom modes appear in instructions', () async {
      final provider = AgentModeProvider(
        options: AgentModeProviderOptions()
          ..modes = [
            AgentMode('draft', 'Drafting mode description.'),
            AgentMode('review', 'Review mode description.'),
          ],
      );

      final result = await provider.invoking(createInvokingContext());

      expect(result.instructions, contains('draft'));
      expect(result.instructions, contains('Drafting mode description.'));
      expect(result.instructions, contains('review'));
      expect(result.instructions, contains('Review mode description.'));
    });

    test('agent mode requires name and description', () {
      expect(() => AgentMode('', 'desc'), throwsArgumentError);
      expect(() => AgentMode('name', ''), throwsArgumentError);
      expect(() => AgentMode(null, 'desc'), throwsArgumentError);
      expect(() => AgentMode('name', null), throwsArgumentError);
    });

    test('duplicate mode names throw', () {
      final options = AgentModeProviderOptions()
        ..modes = [
          AgentMode('draft', 'First draft.'),
          AgentMode('draft', 'Second draft.'),
        ];

      expect(() => AgentModeProvider(options: options), throwsArgumentError);
    });

    test('null mode entry throws', () {
      final options = AgentModeProviderOptions()..modes = [null];

      expect(() => AgentModeProvider(options: options), throwsArgumentError);
    });
  });

  group('AgentModeProvider external mode change notification', () {
    test('external mode change injects notification message', () async {
      final provider = AgentModeProvider();
      final session = TestSession();
      provider.setMode(session, 'execute');

      final result = await provider.invoking(
        createInvokingContext(session: session),
      );

      expect(result.messages, isNotNull);
      final message = result.messages!.single;
      expect(message.role, ChatRole.user);
      expect(message.text, contains('plan'));
      expect(message.text, contains('execute'));
    });

    test('notification cleared after first read', () async {
      final provider = AgentModeProvider();
      final session = TestSession();
      provider.setMode(session, 'execute');
      final context = createInvokingContext(session: session);

      final result1 = await provider.invoking(context);
      final result2 = await provider.invoking(context);

      expect(result1.messages, isNotNull);
      expect(result2.messages, isNull);
    });

    test('tool mode change does not inject notification', () async {
      final provider = AgentModeProvider();
      final session = TestSession();
      final context = createInvokingContext(session: session);
      final result1 = await provider.invoking(context);
      final setMode = getTool(result1.tools!, 'AgentMode_Set');

      await setMode.invoke(AIFunctionArguments({'mode': 'execute'}));
      final result2 = await provider.invoking(context);

      expect(result2.messages, isNull);
    });

    test('same external mode does not inject notification', () async {
      final provider = AgentModeProvider();
      final session = TestSession();
      provider.setMode(session, 'plan');

      final result = await provider.invoking(
        createInvokingContext(session: session),
      );

      expect(result.messages, isNull);
    });
  });
}

Future<(Iterable<AITool>, AgentModeState, AgentSession)>
createToolsWithState() async {
  final provider = AgentModeProvider();
  final session = TestSession();
  final result = await provider.invoking(
    createInvokingContext(session: session),
  );
  final state = session.stateBag.getValue<AgentModeState>(
    provider.stateKeys[0],
  )!;
  return (result.tools!, state, session);
}

AIFunction getTool(Iterable<AITool> tools, String name) {
  return tools.whereType<AIFunction>().firstWhere((tool) => tool.name == name);
}

InvokingContext createInvokingContext({AgentSession? session}) {
  return InvokingContext(
    TestAgent('Parent', 'Parent agent'),
    session ?? TestSession(),
    AIContext(),
  );
}

AgentResponse agentResponseText(String text) {
  return AgentResponse(message: ChatMessage.fromText(ChatRole.assistant, text));
}

class TestSession extends AgentSession {
  TestSession() : super(AgentSessionStateBag(null));
}

class TestAgent extends AIAgent {
  TestAgent(this._name, this._description);

  final String? _name;
  final String? _description;

  @override
  String? get name => _name;

  @override
  String? get description => _description;

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async {
    return TestSession();
  }

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async {
    return {};
  }

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async {
    return TestSession();
  }

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    return agentResponseText('done');
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) {
    return const Stream.empty();
  }
}

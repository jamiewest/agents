import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/workflows/magentic_default_prompts.dart';
import 'package:agents/src/workflows/magentic_prompt_overrides.dart';
import 'package:agents/src/workflows/magentic_workflow_builder.dart';
import 'package:agents/src/workflows/specialized/magentic/magentic_orchestrator.dart';
import 'package:agents/src/workflows/specialized/magentic/magentic_task_context.dart';
import 'package:agents/src/workflows/executor_instance_binding.dart';
import 'package:agents/src/workflows/specialized/magentic/prompt_templates.dart';
import 'package:agents/src/workflows/workflow.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  MagenticTaskContext context({
    String task = 'Find the answer',
    String? responseLanguage,
    MagenticPromptOverrides? promptOverrides,
  }) => MagenticTaskContext(
    [ChatMessage.fromText(ChatRole.user, task)],
    [_NamedAgent('Researcher', 'Looks things up')],
    const TaskLimits(),
    null,
    responseLanguage: responseLanguage,
    promptOverrides: promptOverrides,
  );

  group('placeholder substitution', () {
    test('fills the default templates', () {
      final prompt = context().toTaskLedgerFactsPrompt();

      expect(prompt, contains('Find the answer'));
      expect(prompt, isNot(contains('{task}')));
    });

    test('fills every token of the full ledger prompt', () {
      final ctx = context()
        ..taskLedger = TaskLedger(
          ChatMessage.fromText(ChatRole.assistant, 'THE FACTS'),
          ChatMessage.fromText(ChatRole.assistant, 'THE PLAN'),
        );

      final prompt = ctx.toTaskLedgerFullPrompt();

      expect(prompt, contains('Find the answer'));
      expect(prompt, contains('Researcher'));
      expect(prompt, contains('THE FACTS'));
      expect(prompt, contains('THE PLAN'));
      expect(prompt, isNot(matches(RegExp(r'\{\w+\}'))));
    });

    test('leaves an unavailable placeholder as literal text', () {
      final prompt = context(
        promptOverrides: const MagenticPromptOverrides(
          finalAnswerPrompt: 'Answer {task} in the shape {"a": 1} and {team}.',
        ),
      ).toFinalAnswerPrompt();

      expect(prompt, startsWith('Answer Find the answer'));
      expect(prompt, contains('in the shape'));
      // `{"a": 1}` is not a `{word}` token, and `{team}` is not offered to
      // this prompt, so both survive verbatim.
      expect(prompt, contains('{"a": 1}'));
      expect(prompt, contains('{team}'));
    });

    test('does not rescan a substituted value for placeholders', () {
      final prompt = context(
        task: 'Explain {team} to me',
      ).toFinalAnswerPrompt();

      expect(prompt, contains('Explain {team} to me'));
      expect(prompt, isNot(contains('Looks things up')));
      expect(prompt, isNot(contains('Researcher')));
    });
  });

  group('prompt overrides', () {
    test('replace only the prompt they name', () {
      final ctx = context(
        promptOverrides: const MagenticPromptOverrides(
          finalAnswerPrompt: 'Wrap up: {task}',
        ),
      );

      // `task` carries the trailing newline that joining the task messages
      // produces, so match on the prefix rather than the exact string.
      expect(ctx.toFinalAnswerPrompt(), startsWith('Wrap up: Find the answer'));
      expect(ctx.toTaskLedgerFactsPrompt(), contains('Here is the pre-survey'));
    });

    test('can be based on a default template', () {
      final ctx = context(
        promptOverrides: MagenticPromptOverrides(
          finalAnswerPrompt:
              '${MagenticDefaultPrompts.finalAnswerPrompt}\n\nBe brief.',
        ),
      );

      final prompt = ctx.toFinalAnswerPrompt();

      expect(prompt, contains('Find the answer'));
      expect(prompt, endsWith('Be brief.'));
    });
  });

  group('MagenticWorkflowBuilder', () {
    test('threads overrides and language to the orchestrator', () {
      const overrides = MagenticPromptOverrides(finalAnswerPrompt: 'Wrap up.');
      final workflow = MagenticWorkflowBuilder(_NamedAgent('Manager', 'Leads'))
          .addParticipants([_NamedAgent('Researcher', 'Looks things up')])
          .withResponseLanguage('Norwegian')
          .withPromptOverrides(overrides)
          .build();

      final orchestrator = _orchestratorOf(workflow);

      expect(orchestrator.responseLanguage, 'Norwegian');
      expect(orchestrator.promptOverrides, same(overrides));
    });

    test('leaves both unset by default', () {
      final workflow = MagenticWorkflowBuilder(
        _NamedAgent('Manager', 'Leads'),
      ).addParticipants([_NamedAgent('Researcher', 'Looks things up')]).build();

      final orchestrator = _orchestratorOf(workflow);

      expect(orchestrator.responseLanguage, isNull);
      expect(orchestrator.promptOverrides, isNull);
    });
  });

  group('response language', () {
    test('appends a directive after the body', () {
      final prompt = context(
        responseLanguage: 'Norwegian',
      ).toTaskLedgerFactsPrompt();

      expect(prompt, contains('Find the answer'));
      expect(prompt, endsWith('Do not use any other language.'));
      expect(prompt, contains('Write your entire response in Norwegian'));
    });

    test('appends the JSON-preserving directive to the progress ledger', () {
      final prompt = context(
        responseLanguage: 'Norwegian',
      ).toProgressLedgerPrompt();

      expect(prompt, contains('Do not translate the JSON keys'));
      expect(prompt, contains('"next_speaker"'));
    });

    test('appends nothing to the assembly-only full ledger prompt', () {
      final ctx = context(responseLanguage: 'Norwegian')
        ..taskLedger = TaskLedger(
          ChatMessage.fromText(ChatRole.assistant, 'facts'),
          ChatMessage.fromText(ChatRole.assistant, 'plan'),
        );

      expect(
        ctx.toTaskLedgerFullPrompt(),
        isNot(contains('Write your entire response in')),
      );
    });

    test('appends the directive after an override body', () {
      final prompt = context(
        responseLanguage: 'Norwegian',
        promptOverrides: const MagenticPromptOverrides(
          finalAnswerPrompt: 'Wrap up: {task}',
        ),
      ).toFinalAnswerPrompt();

      expect(prompt, startsWith('Wrap up: Find the answer'));
      expect(prompt, contains('Write your entire response in Norwegian'));
    });

    test('is absent when no language is configured', () {
      expect(
        context().toTaskLedgerFactsPrompt(),
        isNot(contains('Write your entire response in')),
      );
    });
  });
}

MagenticOrchestrator _orchestratorOf(Workflow workflow) => workflow
    .reflectExecutors()
    .whereType<ExecutorInstanceBinding>()
    .map((binding) => binding.executor)
    .whereType<MagenticOrchestrator>()
    .single;

class _NamedAgent extends AIAgent {
  _NamedAgent(this._name, this._description);

  final String _name;
  final String _description;

  @override
  String? get name => _name;

  @override
  String? get description => _description;

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
  }) async => null;

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

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}

// ignore_for_file: non_constant_identifier_names

import 'dart:io';

import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import 'package:agents/src/ai/microsoft_agents_ai/skills/agent_in_memory_skills_source.dart';
import 'package:agents/src/ai/microsoft_agents_ai/skills/agent_skill_frontmatter.dart';
import 'package:agents/src/ai/microsoft_agents_ai/skills/agent_skills_provider.dart';
import 'package:agents/src/ai/microsoft_agents_ai/skills/agent_skills_provider_builder.dart';
import 'package:agents/src/ai/microsoft_agents_ai/skills/agent_skills_provider_options.dart';
import 'package:agents/src/ai/microsoft_agents_ai/skills/aggregating_agent_skills_source.dart';
import 'package:agents/src/ai/microsoft_agents_ai/skills/decorators/deduplicating_agent_skills_source.dart';
import 'package:agents/src/ai/microsoft_agents_ai/skills/decorators/filtering_agent_skills_source.dart';
import 'package:agents/src/ai/microsoft_agents_ai/skills/file/agent_file_skill.dart';
import 'package:agents/src/ai/microsoft_agents_ai/skills/file/agent_file_skill_script.dart';
import 'package:agents/src/ai/microsoft_agents_ai/skills/file/agent_file_skills_source.dart';
import 'package:agents/src/ai/microsoft_agents_ai/skills/file/agent_file_skills_source_options.dart';
import 'package:agents/src/ai/microsoft_agents_ai/skills/programmatic/agent_inline_skill.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('AgentSkillFrontmatter', () {
    test('validates names descriptions and compatibility', () {
      final frontmatter = AgentSkillFrontmatter(
        'weather-tools',
        'Helps with weather tasks.',
        compatibility: 'all agents',
      );

      expect(frontmatter.name, 'weather-tools');
      expect(frontmatter.description, 'Helps with weather tasks.');
      expect(frontmatter.compatibility, 'all agents');

      expect(
        () => AgentSkillFrontmatter('BadName', 'description'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => AgentSkillFrontmatter('valid-name', ''),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => frontmatter.compatibility = 'x' * 501,
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('AgentSkillsSource', () {
    test(
      'in-memory, aggregating, filtering, and deduplicating sources',
      () async {
        final first = _skill('alpha', 'Alpha skill');
        final duplicate = _skill('alpha', 'Duplicate alpha');
        final beta = _skill('beta', 'Beta skill');

        final aggregate = AggregatingAgentSkillsSource([
          AgentInMemorySkillsSource([first, duplicate]),
          AgentInMemorySkillsSource([beta]),
        ]);
        final filtered = FilteringAgentSkillsSource(
          aggregate,
          (skill) => skill.frontmatter.name != 'beta',
        );
        final deduplicated = DeduplicatingAgentSkillsSource(filtered);

        final skills = await deduplicated.getSkills();

        expect(skills, [first]);
      },
    );
  });

  group('AgentInlineSkill', () {
    test('builds content and exposes resources and scripts', () async {
      final skill = _skill('inline-skill', 'Inline skill')
        ..addResource('guide', 'A guide', value: 'resource text')
        ..addScript('echo', () => 'script result', description: 'Echoes');

      expect(skill.content, contains('<name>inline-skill</name>'));
      expect(skill.content, contains('<resource name="guide"'));
      expect(skill.content, contains('<script name="echo"'));
      expect(await skill.resources!.single.read(), 'resource text');
      expect(
        await skill.scripts!.single.run(skill, null, null),
        'script result',
      );
    });
  });

  group('AgentSkillsProvider', () {
    test('returns instructions and load/read/run tools', () async {
      final skill = _skill('planning', 'Planning helper')
        ..addResource('guide', 'A guide', value: 'resource text')
        ..addScript('echo', () => 'script result');
      final provider = AgentSkillsProvider(skills: [skill]);

      final context = await provider.provideAIContext(
        InvokingContext(_TestAgent(), _TestSession(), AIContext()),
      );
      final tools = context.tools!.cast<AIFunction>().toList();

      expect(context.instructions, contains('<name>planning</name>'));
      expect(tools.map((tool) => tool.name), [
        'load_skill',
        'read_skill_resource',
        'run_skill_script',
      ]);

      expect(
        await tools[0].invoke(AIFunctionArguments({'skillName': 'planning'})),
        contains('Use this skill carefully.'),
      );
      expect(
        await tools[1].invoke(
          AIFunctionArguments({
            'skillName': 'planning',
            'resourceName': 'guide',
          }),
        ),
        'resource text',
      );
      expect(
        await tools[2].invoke(
          AIFunctionArguments({'skillName': 'planning', 'scriptName': 'echo'}),
        ),
        'script result',
      );
    });

    test('supports custom prompt validation and caching option', () async {
      expect(
        () => AgentSkillsProvider(
          skills: [_skill('alpha', 'Alpha')],
          options: AgentSkillsProviderOptions()
            ..skillsInstructionPrompt = '{skills}',
        ),
        throwsA(isA<ArgumentError>()),
      );

      final source = _CountingSource([_skill('alpha', 'Alpha')]);
      final provider = AgentSkillsProvider(
        source: source,
        options: AgentSkillsProviderOptions()
          ..disableCaching = false
          ..skillsInstructionPrompt =
              'Skills:\n{skills}\n{resource_instructions}\n{script_instructions}',
      );

      await provider.provideAIContext(
        InvokingContext(_TestAgent(), _TestSession(), AIContext()),
      );
      await provider.provideAIContext(
        InvokingContext(_TestAgent(), _TestSession(), AIContext()),
      );

      expect(source.count, 1);
    });

    test('builder composes sources filter and deduplication', () async {
      final provider = AgentSkillsProviderBuilder()
          .useSkills([
            _skill('alpha', 'Alpha'),
            _skill('alpha', 'Duplicate'),
            _skill('beta', 'Beta'),
          ])
          .useFilter((skill) => skill.frontmatter.name != 'beta')
          .build();

      final context = await provider.provideAIContext(
        InvokingContext(_TestAgent(), _TestSession(), AIContext()),
      );

      expect(context.instructions, contains('<name>alpha</name>'));
      expect(context.instructions, isNot(contains('<name>beta</name>')));
    });
  });

  group('AgentFileSkillsSource', () {
    test('discovers skills resources and scripts from files', () async {
      final root = await Directory.systemTemp.createTemp('agent_skills_test_');
      addTearDown(() => root.deleteSync(recursive: true));
      final skillDir = Directory('${root.path}/file-skill')..createSync();
      File('${skillDir.path}/SKILL.md').writeAsStringSync('''
---
name: file-skill
description: File backed skill
license: MIT
metadata:
  owner: test
---
Use the file skill.
''');
      Directory('${skillDir.path}/references').createSync();
      File('${skillDir.path}/references/guide.md').writeAsStringSync('guide');
      Directory('${skillDir.path}/scripts').createSync();
      File('${skillDir.path}/scripts/run.sh').writeAsStringSync('echo hi');

      final source = AgentFileSkillsSource(
        [root.path],
        scriptRunner:
            (
              skill,
              script,
              arguments,
              serviceProvider, {
              cancellationToken,
            }) async => 'ran ${script.name}',
      );

      final skills = await source.getSkills();
      final skill = skills.single as AgentFileSkill;

      expect(skill.frontmatter.name, 'file-skill');
      expect(skill.frontmatter.metadata, containsPair('owner', 'test'));
      expect(skill.resources.single.name, 'references/guide.md');
      expect(await skill.resources.single.read(), 'guide');
      expect(skill.scripts.single, isA<AgentFileSkillScript>());
      expect(
        await skill.scripts.single.run(skill, null, null),
        'ran scripts/run.sh',
      );
    });

    test('normalizes directories and validates extensions', () {
      expect(
        AgentFileSkillsSource.normalizePath(r'.\references\guide.md'),
        'references/guide.md',
      );
      expect(
        () => AgentFileSkillsSource.validateExtensions(['txt']),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        AgentFileSkillsSource.validateAndNormalizeDirectoryNames([
          '.',
          r'./refs',
          '../bad',
        ], NullLogger.instance).toList(),
        ['.', 'refs'],
      );
    });

    test('skips invalid frontmatter and mismatched directory names', () async {
      final root = await Directory.systemTemp.createTemp('agent_skills_bad_');
      addTearDown(() => root.deleteSync(recursive: true));
      final skillDir = Directory('${root.path}/actual-name')..createSync();
      File('${skillDir.path}/SKILL.md').writeAsStringSync('''
---
name: other-name
description: Mismatch
---
content
''');

      final source = AgentFileSkillsSource([root.path]);

      expect(await source.getSkills(), isEmpty);
    });
  });
}

AgentInlineSkill _skill(String name, String description) {
  return AgentInlineSkill(
    'Use this skill carefully.',
    name: name,
    description: description,
  );
}

class _CountingSource extends AgentInMemorySkillsSource {
  _CountingSource(super.skills);

  int count = 0;

  @override
  Future<List<AgentInlineSkill>> getSkills({
    CancellationToken? cancellationToken,
  }) async {
    count++;
    return (await super.getSkills(
      cancellationToken: cancellationToken,
    )).cast<AgentInlineSkill>();
  }
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}

class _TestAgent extends AIAgent {
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

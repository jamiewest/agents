
import 'dart:io';

import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/ai_context.dart';
import 'package:agents/src/ai/skills/agent_in_memory_skills_source.dart';
import 'package:agents/src/ai/skills/agent_skill_frontmatter.dart';
import 'package:agents/src/ai/skills/agent_skills_provider.dart';
import 'package:agents/src/ai/skills/agent_skills_provider_builder.dart';
import 'package:agents/src/ai/skills/agent_skills_provider_options.dart';
import 'package:agents/src/ai/skills/agent_skills_source_context.dart';
import 'package:agents/src/ai/skills/aggregating_agent_skills_source.dart';
import 'package:agents/src/ai/skills/decorators/caching_agent_skills_source.dart';
import 'package:agents/src/ai/skills/decorators/caching_agent_skills_source_options.dart';
import 'package:agents/src/ai/skills/decorators/deduplicating_agent_skills_source.dart';
import 'package:agents/src/ai/skills/decorators/filtering_agent_skills_source.dart';
import 'package:agents/src/ai/skills/file/agent_file_skill.dart';
import 'package:agents/src/ai/skills/file/agent_file_skill_script.dart';
import 'package:agents/src/ai/skills/file/agent_file_skills_source.dart';
import 'package:agents/src/ai/skills/file/agent_file_skills_source_options.dart';
import 'package:agents/src/ai/skills/programmatic/agent_inline_skill.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';
import 'package:agents/src/abstractions/invoking_context.dart';

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
          (skill, context) => skill.frontmatter.name != 'beta',
        );
        final deduplicated = DeduplicatingAgentSkillsSource(filtered);

        final skills = await deduplicated.getSkills(_skillsContext);

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
        InvokingContext(_TestAgent(), _TestSession(), null, AIContext()),
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

    test('supports custom prompt validation and pipeline caching', () async {
      expect(
        () => AgentSkillsProvider(
          skills: [_skill('alpha', 'Alpha')],
          options: AgentSkillsProviderOptions()
            ..skillsInstructionPrompt = 'missing skills placeholder',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Caching lives in the source pipeline now: a caller-supplied source
      // is invoked per request unless wrapped in CachingAgentSkillsSource.
      final uncached = _CountingSource([_skill('alpha', 'Alpha')]);
      final uncachedProvider = AgentSkillsProvider(
        source: uncached,
        options: AgentSkillsProviderOptions()
          ..skillsInstructionPrompt = 'Skills:\n{skills}',
      );
      await uncachedProvider.provideAIContext(
        InvokingContext(_TestAgent(), _TestSession(), null, AIContext()),
      );
      await uncachedProvider.provideAIContext(
        InvokingContext(_TestAgent(), _TestSession(), null, AIContext()),
      );
      expect(uncached.count, 2);

      final cached = _CountingSource([_skill('alpha', 'Alpha')]);
      final cachedProvider = AgentSkillsProvider(
        source: CachingAgentSkillsSource(cached),
      );
      await cachedProvider.provideAIContext(
        InvokingContext(_TestAgent(), _TestSession(), null, AIContext()),
      );
      await cachedProvider.provideAIContext(
        InvokingContext(_TestAgent(), _TestSession(), null, AIContext()),
      );
      expect(cached.count, 1);
    });

    test('builder caches by default and disableCaching opts out', () async {
      final cachedSource = _CountingSource([_skill('alpha', 'Alpha')]);
      final cachedProvider = AgentSkillsProviderBuilder()
          .useSource(cachedSource)
          .build();
      await cachedProvider.provideAIContext(
        InvokingContext(_TestAgent(), _TestSession(), null, AIContext()),
      );
      await cachedProvider.provideAIContext(
        InvokingContext(_TestAgent(), _TestSession(), null, AIContext()),
      );
      expect(cachedSource.count, 1);

      final uncachedSource = _CountingSource([_skill('alpha', 'Alpha')]);
      final uncachedProvider = AgentSkillsProviderBuilder()
          .useSource(uncachedSource)
          .disableCaching()
          .build();
      await uncachedProvider.provideAIContext(
        InvokingContext(_TestAgent(), _TestSession(), null, AIContext()),
      );
      await uncachedProvider.provideAIContext(
        InvokingContext(_TestAgent(), _TestSession(), null, AIContext()),
      );
      expect(uncachedSource.count, 2);
    });

    test('build disposes owned pipeline when provider is disposed', () {
      final source = _CountingSource([_skill('alpha', 'Alpha')]);
      AgentSkillsProviderBuilder().useSource(source).build().dispose();

      expect(source.disposed, isTrue);
    });

    test('tools are approval-wrapped unless disabled', () async {
      final skill = _skill('planning', 'Planning skill')
        ..addResource('guide', 'A guide', value: 'resource text')
        ..addScript('echo', () => 'script result');

      final guarded = await AgentSkillsProvider(skills: [skill])
          .provideAIContext(
            InvokingContext(_TestAgent(), _TestSession(), null, AIContext()),
          );
      expect(guarded.tools, everyElement(isA<ApprovalRequiredAIFunction>()));

      final open =
          await AgentSkillsProvider(
            skills: [skill],
            options: AgentSkillsProviderOptions()
              ..disableLoadSkillApproval = true
              ..disableReadSkillResourceApproval = true
              ..disableRunSkillScriptApproval = true,
          ).provideAIContext(
            InvokingContext(_TestAgent(), _TestSession(), null, AIContext()),
          );
      expect(
        open.tools,
        everyElement(isNot(isA<ApprovalRequiredAIFunction>())),
      );
    });

    test('auto-approval rules match skill tool names', () async {
      expect(
        await AgentSkillsProvider.readOnlyToolsAutoApprovalRule(
          FunctionCallContent(callId: 'c1', name: 'load_skill'),
        ),
        isTrue,
      );
      expect(
        await AgentSkillsProvider.readOnlyToolsAutoApprovalRule(
          FunctionCallContent(callId: 'c2', name: 'run_skill_script'),
        ),
        isFalse,
      );
      expect(
        await AgentSkillsProvider.allToolsAutoApprovalRule(
          FunctionCallContent(callId: 'c3', name: 'run_skill_script'),
        ),
        isTrue,
      );
      expect(
        await AgentSkillsProvider.allToolsAutoApprovalRule(
          FunctionCallContent(callId: 'c4', name: 'other_tool'),
        ),
        isFalse,
      );
    });

    test('builder composes sources filter and deduplication', () async {
      final provider = AgentSkillsProviderBuilder()
          .useSkills([
            _skill('alpha', 'Alpha'),
            _skill('alpha', 'Duplicate'),
            _skill('beta', 'Beta'),
          ])
          .useFilter((skill, context) => skill.frontmatter.name != 'beta')
          .build();

      final context = await provider.provideAIContext(
        InvokingContext(_TestAgent(), _TestSession(), null, AIContext()),
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

      final skills = await source.getSkills(_skillsContext);
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

    test('honors resource search depth', () async {
      final root = await Directory.systemTemp.createTemp(
        'agent_skills_depth_test_',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final skillDir = Directory('${root.path}/depth-skill')..createSync();
      File('${skillDir.path}/SKILL.md').writeAsStringSync('''
---
name: depth-skill
description: Depth skill
---
Use the depth skill.
''');
      Directory(
        '${skillDir.path}/references/nested',
      ).createSync(recursive: true);
      File(
        '${skillDir.path}/references/nested/guide.md',
      ).writeAsStringSync('guide');

      final shallow = await AgentFileSkillsSource([
        root.path,
      ]).getSkills(_skillsContext);
      expect(shallow.single.resources, isEmpty);

      final deep = await AgentFileSkillsSource(
        [root.path],
        options: AgentFileSkillsSourceOptions()..resourceSearchDepth = 2,
      ).getSkills(_skillsContext);
      expect(deep.single.resources!.single.name, 'references/nested/guide.md');
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

      expect(await source.getSkills(_skillsContext), isEmpty);
    });

    test('applies script and resource filters', () async {
      final root = await Directory.systemTemp.createTemp(
        'agent_skills_filter_',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final skillDir = Directory('${root.path}/filter-skill')..createSync();
      File('${skillDir.path}/SKILL.md').writeAsStringSync('''
---
name: filter-skill
description: Filter skill
---
Use the filter skill.
''');
      Directory('${skillDir.path}/references').createSync();
      File('${skillDir.path}/references/keep.md').writeAsStringSync('keep');
      File('${skillDir.path}/references/drop.md').writeAsStringSync('drop');
      Directory('${skillDir.path}/scripts').createSync();
      File('${skillDir.path}/scripts/keep.sh').writeAsStringSync('echo keep');
      File('${skillDir.path}/scripts/drop.sh').writeAsStringSync('echo drop');

      final source = AgentFileSkillsSource(
        [root.path],
        scriptRunner:
            (
              skill,
              script,
              arguments,
              serviceProvider, {
              cancellationToken,
            }) async => '',
        options: AgentFileSkillsSourceOptions()
          ..resourceFilter = ((ctx) =>
              !ctx.relativeFilePath.endsWith('drop.md'))
          ..scriptFilter = ((ctx) => !ctx.relativeFilePath.endsWith('drop.sh')),
      );

      final skill =
          (await source.getSkills(_skillsContext)).single as AgentFileSkill;
      expect(skill.resources.map((r) => r.name), ['references/keep.md']);
      expect(skill.scripts.map((s) => s.name), ['scripts/keep.sh']);
    });
  });

  group('CachingAgentSkillsSource', () {
    test('caches the inner result across calls', () async {
      final inner = _CountingSource([_skill('alpha', 'Alpha')]);
      final caching = CachingAgentSkillsSource(inner);

      await caching.getSkills(_skillsContext);
      await caching.getSkills(_skillsContext);

      expect(inner.count, 1);
    });

    test('concurrent callers share a single in-flight fetch', () async {
      final inner = _CountingSource([_skill('alpha', 'Alpha')]);
      final caching = CachingAgentSkillsSource(inner);

      final results = await Future.wait([
        caching.getSkills(_skillsContext),
        caching.getSkills(_skillsContext),
      ]);

      expect(inner.count, 1);
      expect(results[0], same(results[1]));
    });

    test('refreshInterval of zero re-fetches every call', () async {
      final inner = _CountingSource([_skill('alpha', 'Alpha')]);
      final caching = CachingAgentSkillsSource(
        inner,
        options: CachingAgentSkillsSourceOptions()
          ..refreshInterval = Duration.zero,
      );

      await caching.getSkills(_skillsContext);
      await caching.getSkills(_skillsContext);

      expect(inner.count, 2);
    });

    test('caches per isolation key', () async {
      final inner = _CountingSource([_skill('alpha', 'Alpha')]);
      var key = 'a';
      final caching = CachingAgentSkillsSource(
        inner,
        options: CachingAgentSkillsSourceOptions()
          ..cacheIsolationKeySelector = (_) => key,
      );

      await caching.getSkills(_skillsContext);
      await caching.getSkills(_skillsContext);
      expect(inner.count, 1);

      key = 'b';
      await caching.getSkills(_skillsContext);
      expect(inner.count, 2);
    });

    test('dispose disposes the inner source and rejects further calls', () {
      final inner = _CountingSource([_skill('alpha', 'Alpha')]);
      final caching = CachingAgentSkillsSource(inner)..dispose();

      expect(inner.disposed, isTrue);
      expect(caching.getSkills(_skillsContext), throwsStateError);
    });
  });
}

final _skillsContext = AgentSkillsSourceContext(_TestAgent(), null);

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
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  @override
  Future<List<AgentInlineSkill>> getSkills(
    AgentSkillsSourceContext context, {
    CancellationToken? cancellationToken,
  }) async {
    count++;
    return (await super.getSkills(
      context,
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

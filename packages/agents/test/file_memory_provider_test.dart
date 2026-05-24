import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_context.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/ai_context.dart';
import 'package:agents/src/abstractions/ai_context_provider.dart';
import 'package:agents/src/ai/harness/file_memory/file_list_entry.dart';
import 'package:agents/src/ai/harness/file_memory/file_memory_provider.dart';
import 'package:agents/src/ai/harness/file_memory/file_memory_provider_options.dart';
import 'package:agents/src/ai/harness/file_memory/file_memory_state.dart';
import 'package:agents/src/ai/harness/file_store/file_search_result.dart';
import 'package:agents/src/ai/harness/file_store/in_memory_agent_file_store.dart';

void main() {
  group('FileMemoryProvider constructor', () {
    test('null file store throws', () {
      expect(() => FileMemoryProvider(null), throwsArgumentError);
    });

    test('with defaults succeeds', () {
      final provider = FileMemoryProvider(InMemoryAgentFileStore());

      expect(provider, isNotNull);
    });

    test('with state initializer succeeds', () {
      final provider = FileMemoryProvider(
        InMemoryAgentFileStore(),
        stateInitializer: (_) => FileMemoryState()..workingFolder = 'custom',
      );

      expect(provider, isNotNull);
    });
  });

  group('FileMemoryProvider context', () {
    test('returns tools and instructions', () async {
      final (tools, _, _) = await createTools();

      expect(tools, hasLength(5));
      expect(
        tools.whereType<AIFunction>().map((t) => t.name),
        unorderedEquals([
          'FileMemory_SaveFile',
          'FileMemory_ReadFile',
          'FileMemory_DeleteFile',
          'FileMemory_ListFiles',
          'FileMemory_SearchFiles',
        ]),
      );
    });

    test('returns instructions', () async {
      final provider = FileMemoryProvider(InMemoryAgentFileStore());

      final result = await provider.invoking(createInvokingContext());

      expect(result.instructions, isNotNull);
      expect(result.instructions, contains('file-based memory'));
      expect(result.instructions, contains('compacted'));
    });

    test('no files does not inject memory index message', () async {
      final provider = FileMemoryProvider(InMemoryAgentFileStore());

      final result = await provider.invoking(createInvokingContext());

      expect(result.messages, isNull);
    });
  });

  group('FileMemoryProvider save file', () {
    test('creates file', () async {
      final store = InMemoryAgentFileStore();
      final (tools, _, session) = await createTools(store);
      final saveFile = getTool(tools, 'FileMemory_SaveFile');

      await invokeWithRunContext(
        saveFile,
        AIFunctionArguments({
          'fileName': 'notes.md',
          'content': 'Test content',
          'description': '',
        }),
        session,
      );

      expect(await store.readFileAsync('notes.md'), 'Test content');
    });

    test('with description creates both files', () async {
      final store = InMemoryAgentFileStore();
      final (tools, _, session) = await createTools(store);
      final saveFile = getTool(tools, 'FileMemory_SaveFile');

      await invokeWithRunContext(
        saveFile,
        AIFunctionArguments({
          'fileName': 'research.md',
          'content': 'Long research content...',
          'description': 'Summary of research findings',
        }),
        session,
      );

      expect(
        await store.readFileAsync('research.md'),
        'Long research content...',
      );
      expect(
        await store.readFileAsync('research_description.md'),
        'Summary of research findings',
      );
    });

    test('without description deletes stale description', () async {
      final store = InMemoryAgentFileStore();
      final (tools, _, session) = await createTools(store);
      final saveFile = getTool(tools, 'FileMemory_SaveFile');

      await invokeWithRunContext(
        saveFile,
        AIFunctionArguments({
          'fileName': 'notes.md',
          'content': 'Original',
          'description': 'Old description',
        }),
        session,
      );
      expect(await store.readFileAsync('notes_description.md'), isNotNull);

      await invokeWithRunContext(
        saveFile,
        AIFunctionArguments({'fileName': 'notes.md', 'content': 'Updated'}),
        session,
      );

      expect(await store.readFileAsync('notes.md'), 'Updated');
      expect(await store.readFileAsync('notes_description.md'), isNull);
    });

    test('with custom state creates in subfolder', () async {
      final store = InMemoryAgentFileStore();
      final (tools, state, session) = await createTools(
        store,
        (_) => FileMemoryState()..workingFolder = 'session123',
      );
      final saveFile = getTool(tools, 'FileMemory_SaveFile');

      await invokeWithRunContext(
        saveFile,
        AIFunctionArguments({
          'fileName': 'notes.md',
          'content': 'Session content',
          'description': '',
        }),
        session,
      );

      expect(state.workingFolder, 'session123');
      expect(
        await store.readFileAsync('session123/notes.md'),
        'Session content',
      );
    });

    test('returns confirmation', () async {
      final (tools, _, session) = await createTools();
      final saveFile = getTool(tools, 'FileMemory_SaveFile');

      final result = await invokeWithRunContext(
        saveFile,
        AIFunctionArguments({'fileName': 'notes.md', 'content': 'Content'}),
        session,
      );

      expect(result, isA<String>().having((s) => s, 'text', contains('saved')));
    });
  });

  group('FileMemoryProvider read file', () {
    test('existing file returns content', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'Stored content');
      final (tools, _, session) = await createTools(store);
      final readFile = getTool(tools, 'FileMemory_ReadFile');

      final result = await invokeWithRunContext(
        readFile,
        AIFunctionArguments({'fileName': 'notes.md'}),
        session,
      );

      expect(result, 'Stored content');
    });

    test('non-existent returns not found message', () async {
      final (tools, _, session) = await createTools();
      final readFile = getTool(tools, 'FileMemory_ReadFile');

      final result = await invokeWithRunContext(
        readFile,
        AIFunctionArguments({'fileName': 'nonexistent.md'}),
        session,
      );

      expect(
        result,
        isA<String>().having((s) => s, 'text', contains('not found')),
      );
    });
  });

  group('FileMemoryProvider delete file', () {
    test('existing file deletes and returns confirmation', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'Content');
      final (tools, _, session) = await createTools(store);
      final deleteFile = getTool(tools, 'FileMemory_DeleteFile');

      final result = await invokeWithRunContext(
        deleteFile,
        AIFunctionArguments({'fileName': 'notes.md'}),
        session,
      );

      expect(
        result,
        isA<String>().having((s) => s, 'text', contains('deleted')),
      );
      expect(await store.fileExistsAsync('notes.md'), isFalse);
    });

    test('also deletes description file', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'Content');
      await store.writeFileAsync('notes_description.md', 'Description');
      final (tools, _, session) = await createTools(store);
      final deleteFile = getTool(tools, 'FileMemory_DeleteFile');

      await invokeWithRunContext(
        deleteFile,
        AIFunctionArguments({'fileName': 'notes.md'}),
        session,
      );

      expect(await store.fileExistsAsync('notes.md'), isFalse);
      expect(await store.fileExistsAsync('notes_description.md'), isFalse);
    });
  });

  group('FileMemoryProvider list files', () {
    test('returns files with descriptions', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'Content');
      await store.writeFileAsync('notes_description.md', 'A description');
      await store.writeFileAsync('other.md', 'Other content');
      final (tools, _, session) = await createTools(store);
      final listFiles = getTool(tools, 'FileMemory_ListFiles');

      final result = await invokeWithRunContext(
        listFiles,
        AIFunctionArguments(),
        session,
      );

      final entries = result as List<FileListEntry>;
      expect(entries, hasLength(2));
      final notesEntry = entries.firstWhere((e) => e.fileName == 'notes.md');
      expect(notesEntry.description, 'A description');
      final otherEntry = entries.firstWhere((e) => e.fileName == 'other.md');
      expect(otherEntry.description, isNull);
    });

    test('hides description files', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'Content');
      await store.writeFileAsync('notes_description.md', 'Desc');
      final (tools, _, session) = await createTools(store);
      final listFiles = getTool(tools, 'FileMemory_ListFiles');

      final result = await invokeWithRunContext(
        listFiles,
        AIFunctionArguments(),
        session,
      );

      final entries = result as List<FileListEntry>;
      expect(entries, hasLength(1));
      expect(entries[0].fileName, 'notes.md');
    });
  });

  group('FileMemoryProvider search files', () {
    test('finds matching content', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync(
        'notes.md',
        'Important research findings about AI',
      );
      final (tools, _, session) = await createTools(store);
      final searchFiles = getTool(tools, 'FileMemory_SearchFiles');

      final result = await invokeWithRunContext(
        searchFiles,
        AIFunctionArguments({
          'regexPattern': 'research findings',
          'filePattern': '',
        }),
        session,
      );

      final entries = result as List<FileSearchResult>;
      expect(entries, hasLength(1));
      expect(entries[0].fileName, 'notes.md');
      expect(entries[0].matchingLines, isNotEmpty);
    });

    test('with file pattern filters results', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'Important data');
      await store.writeFileAsync('data.txt', 'Important data');
      final (tools, _, session) = await createTools(store);
      final searchFiles = getTool(tools, 'FileMemory_SearchFiles');

      final result = await invokeWithRunContext(
        searchFiles,
        AIFunctionArguments({
          'regexPattern': 'Important',
          'filePattern': '*.md',
        }),
        session,
      );

      final entries = result as List<FileSearchResult>;
      expect(entries, hasLength(1));
      expect(entries[0].fileName, 'notes.md');
    });

    test('hides internal files', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'Match here');
      await store.writeFileAsync('notes_description.md', 'Match sidecar');
      await store.writeFileAsync('memories.md', 'Match index');
      final (tools, _, session) = await createTools(store);
      final searchFiles = getTool(tools, 'FileMemory_SearchFiles');

      final result = await invokeWithRunContext(
        searchFiles,
        AIFunctionArguments({'regexPattern': 'Match'}),
        session,
      );

      final entries = result as List<FileSearchResult>;
      expect(entries.map((e) => e.fileName), ['notes.md']);
    });
  });

  group('FileMemoryProvider state initializer', () {
    test('custom state initializer sets working folder', () async {
      final (_, state, _) = await createTools(
        InMemoryAgentFileStore(),
        (_) => FileMemoryState()..workingFolder = 'user42',
      );

      expect(state.workingFolder, 'user42');
    });

    test('default state initializer uses empty working folder', () async {
      final (_, state, _) = await createTools();

      expect(state.workingFolder, '');
    });

    test('state persists across invocations', () async {
      final provider = FileMemoryProvider(
        InMemoryAgentFileStore(),
        stateInitializer: (_) =>
            FileMemoryState()..workingFolder = 'persistent',
      );
      final session = TestSession();
      final context = createInvokingContext(session: session);

      await provider.invoking(context);
      final state1 = session.stateBag.getValue<FileMemoryState>(
        provider.stateKeys[0],
      );
      await provider.invoking(context);
      final state2 = session.stateBag.getValue<FileMemoryState>(
        provider.stateKeys[0],
      );

      expect(state1, isNotNull);
      expect(state2, isNotNull);
      expect(state1!.workingFolder, state2!.workingFolder);
    });
  });

  group('FileMemoryProvider path traversal protection', () {
    test('save file path traversal throws', () async {
      final (tools, _, session) = await createTools();
      final saveFile = getTool(tools, 'FileMemory_SaveFile');

      await expectLater(
        invokeWithRunContext(
          saveFile,
          AIFunctionArguments({
            'fileName': '../escape.md',
            'content': 'Content',
            'description': '',
          }),
          session,
        ),
        throwsArgumentError,
      );
    });

    test('save file absolute path throws', () async {
      final (tools, _, session) = await createTools();
      final saveFile = getTool(tools, 'FileMemory_SaveFile');

      await expectLater(
        invokeWithRunContext(
          saveFile,
          AIFunctionArguments({
            'fileName': '/etc/passwd',
            'content': 'Content',
            'description': '',
          }),
          session,
        ),
        throwsArgumentError,
      );
    });

    test('save file drive-rooted path throws', () async {
      final (tools, _, session) = await createTools();
      final saveFile = getTool(tools, 'FileMemory_SaveFile');

      await expectLater(
        invokeWithRunContext(
          saveFile,
          AIFunctionArguments({
            'fileName': r'C:\temp\file.md',
            'content': 'Content',
          }),
          session,
        ),
        throwsArgumentError,
      );
    });

    test('save file double dots in file name allowed', () async {
      final store = InMemoryAgentFileStore();
      final (tools, _, session) = await createTools(store);
      final saveFile = getTool(tools, 'FileMemory_SaveFile');

      await invokeWithRunContext(
        saveFile,
        AIFunctionArguments({'fileName': 'notes..md', 'content': 'Content'}),
        session,
      );

      expect(await store.readFileAsync('notes..md'), 'Content');
    });

    test('reserved internal file name throws', () async {
      final (tools, _, session) = await createTools();
      final saveFile = getTool(tools, 'FileMemory_SaveFile');

      await expectLater(
        invokeWithRunContext(
          saveFile,
          AIFunctionArguments({
            'fileName': 'memories.md',
            'content': 'Content',
          }),
          session,
        ),
        throwsArgumentError,
      );
    });
  });

  group('FileMemoryProvider memory index', () {
    test('save file creates memory index', () async {
      final store = InMemoryAgentFileStore();
      final (tools, _, session) = await createTools(store);
      final saveFile = getTool(tools, 'FileMemory_SaveFile');

      await invokeWithRunContext(
        saveFile,
        AIFunctionArguments({
          'fileName': 'notes.md',
          'content': 'Test content',
        }),
        session,
      );

      final index = await store.readFileAsync('memories.md');
      expect(index, isNotNull);
      expect(index, contains('**notes.md**'));
    });

    test('save file with description index includes description', () async {
      final store = InMemoryAgentFileStore();
      final (tools, _, session) = await createTools(store);
      final saveFile = getTool(tools, 'FileMemory_SaveFile');

      await invokeWithRunContext(
        saveFile,
        AIFunctionArguments({
          'fileName': 'research.md',
          'content': 'Research data',
          'description': 'Key findings',
        }),
        session,
      );

      final index = await store.readFileAsync('memories.md');
      expect(index, isNotNull);
      expect(index, contains('**research.md**: Key findings'));
    });

    test('delete file updates memory index', () async {
      final store = InMemoryAgentFileStore();
      final (tools, _, session) = await createTools(store);
      final saveFile = getTool(tools, 'FileMemory_SaveFile');
      final deleteFile = getTool(tools, 'FileMemory_DeleteFile');

      await invokeWithRunContext(
        saveFile,
        AIFunctionArguments({'fileName': 'notes.md', 'content': 'Content'}),
        session,
      );
      await invokeWithRunContext(
        saveFile,
        AIFunctionArguments({'fileName': 'other.md', 'content': 'Other'}),
        session,
      );

      await invokeWithRunContext(
        deleteFile,
        AIFunctionArguments({'fileName': 'notes.md'}),
        session,
      );

      final index = await store.readFileAsync('memories.md');
      expect(index, isNotNull);
      expect(index, isNot(contains('notes.md')));
      expect(index, contains('**other.md**'));
    });

    test('memory index capped at 50 entries', () async {
      final store = InMemoryAgentFileStore();
      final (tools, _, session) = await createTools(store);
      final saveFile = getTool(tools, 'FileMemory_SaveFile');

      for (var i = 0; i < 55; i++) {
        await invokeWithRunContext(
          saveFile,
          AIFunctionArguments({
            'fileName': 'file${i.toString().padLeft(3, '0')}.md',
            'content': 'Content $i',
          }),
          session,
        );
      }

      final index = await store.readFileAsync('memories.md');
      expect(index, isNotNull);
      final entryCount = index!
          .split('\n')
          .where((line) => line.startsWith('- **'))
          .length;
      expect(entryCount, 50);
    });

    test('list files hides memory index', () async {
      final store = InMemoryAgentFileStore();
      final (tools, _, session) = await createTools(store);
      final saveFile = getTool(tools, 'FileMemory_SaveFile');
      final listFiles = getTool(tools, 'FileMemory_ListFiles');
      await invokeWithRunContext(
        saveFile,
        AIFunctionArguments({'fileName': 'notes.md', 'content': 'Content'}),
        session,
      );

      final result = await invokeWithRunContext(
        listFiles,
        AIFunctionArguments(),
        session,
      );

      final entries = result as List<FileListEntry>;
      expect(entries, hasLength(1));
      expect(entries[0].fileName, 'notes.md');
    });

    test('provide context injects memory index message', () async {
      final store = InMemoryAgentFileStore();
      final provider = FileMemoryProvider(store);
      final session = TestSession();
      final initResult = await provider.invoking(
        createInvokingContext(session: session),
      );
      final saveFile = getTool(initResult.tools!, 'FileMemory_SaveFile');
      await invokeWithRunContext(
        saveFile,
        AIFunctionArguments({
          'fileName': 'research.md',
          'content': 'Data',
          'description': 'Research summary',
        }),
        session,
      );

      final result = await provider.invoking(
        createInvokingContext(session: session),
      );

      expect(result.messages, isNotNull);
      final messages = result.messages!.toList();
      expect(messages, hasLength(1));
      expect(messages[0].role, ChatRole.user);
      expect(messages[0].text.toLowerCase(), contains('memory index'));
      expect(messages[0].text, contains('research.md'));
    });
  });

  group('FileMemoryProvider options', () {
    test('custom instructions override default', () async {
      final provider = FileMemoryProvider(
        InMemoryAgentFileStore(),
        options: FileMemoryProviderOptions()
          ..instructions = 'Custom file memory instructions.',
      );

      final result = await provider.invoking(createInvokingContext());

      expect(result.instructions, 'Custom file memory instructions.');
    });

    test('null options uses default instructions', () async {
      final provider = FileMemoryProvider(InMemoryAgentFileStore());

      final result = await provider.invoking(createInvokingContext());

      expect(result.instructions, contains('file-based memory'));
    });
  });

  group('FileMemoryProvider thread safety', () {
    test('concurrent saves produce consistent index', () async {
      final store = InMemoryAgentFileStore();
      final (tools, _, session) = await createTools(store);
      final saveFile = getTool(tools, 'FileMemory_SaveFile');
      const fileCount = 20;

      await Future.wait(
        List.generate(
          fileCount,
          (i) => invokeWithRunContext(
            saveFile,
            AIFunctionArguments({
              'fileName': 'file$i.md',
              'content': 'Content $i',
              'description': 'Description $i',
            }),
            session,
          ),
        ),
      );

      final indexContent = await store.readFileAsync('memories.md');
      expect(indexContent, isNotNull);
      for (var i = 0; i < fileCount; i++) {
        expect(indexContent, contains('**file$i.md**'));
      }
    });

    test('concurrent save and delete produce consistent index', () async {
      final store = InMemoryAgentFileStore();
      final (tools, _, session) = await createTools(store);
      final saveFile = getTool(tools, 'FileMemory_SaveFile');
      final deleteFile = getTool(tools, 'FileMemory_DeleteFile');

      for (var i = 0; i < 5; i++) {
        await invokeWithRunContext(
          saveFile,
          AIFunctionArguments({
            'fileName': 'delete$i.md',
            'content': 'To be deleted $i',
          }),
          session,
        );
      }

      await Future.wait([
        for (var i = 0; i < 5; i++) ...[
          invokeWithRunContext(
            saveFile,
            AIFunctionArguments({
              'fileName': 'keep$i.md',
              'content': 'Kept $i',
            }),
            session,
          ),
          invokeWithRunContext(
            deleteFile,
            AIFunctionArguments({'fileName': 'delete$i.md'}),
            session,
          ),
        ],
      ]);

      final indexContent = await store.readFileAsync('memories.md');
      expect(indexContent, isNotNull);
      for (var i = 0; i < 5; i++) {
        expect(indexContent, contains('**keep$i.md**'));
        expect(indexContent, isNot(contains('**delete$i.md**')));
      }
    });

    test('dispose releases resources and is idempotent', () {
      final provider = FileMemoryProvider(InMemoryAgentFileStore());

      provider.dispose();
      provider.dispose();
    });

    test('save file after dispose throws', () async {
      final provider = FileMemoryProvider(InMemoryAgentFileStore());
      final session = TestSession();
      final result = await provider.invoking(
        createInvokingContext(session: session),
      );
      final saveFile = getTool(result.tools!, 'FileMemory_SaveFile');
      provider.dispose();

      await expectLater(
        invokeWithRunContext(
          saveFile,
          AIFunctionArguments({
            'fileName': 'notes.md',
            'content': 'Should fail',
          }),
          session,
        ),
        throwsStateError,
      );
    });
  });
}

Future<(Iterable<AITool>, FileMemoryState, AgentSession)> createTools([
  InMemoryAgentFileStore? store,
  FileMemoryState Function(AgentSession?)? stateInitializer,
]) async {
  final provider = FileMemoryProvider(
    store ?? InMemoryAgentFileStore(),
    stateInitializer: stateInitializer,
  );
  final session = TestSession();
  final result = await provider.invoking(
    createInvokingContext(session: session),
  );
  final state = session.stateBag.getValue<FileMemoryState>(
    provider.stateKeys[0],
  )!;
  return (result.tools!, state, session);
}

AIFunction getTool(Iterable<AITool> tools, String name) {
  return tools.whereType<AIFunction>().firstWhere((tool) => tool.name == name);
}

Future<Object?> invokeWithRunContext(
  AIFunction tool,
  AIFunctionArguments arguments,
  AgentSession? session,
) async {
  final previousContext = AIAgent.currentRunContext;
  AIAgent.currentRunContext = AgentRunContext(
    TestAgent('Parent', 'Parent agent'),
    session,
    <ChatMessage>[],
    null,
  );
  try {
    return await tool.invoke(arguments);
  } finally {
    AIAgent.currentRunContext = previousContext;
  }
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

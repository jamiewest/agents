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
import 'package:agents/src/ai/microsoft_agents_ai/harness/file_access/file_access_provider.dart';
import 'package:agents/src/ai/microsoft_agents_ai/harness/file_access/file_access_provider_options.dart';
import 'package:agents/src/ai/microsoft_agents_ai/harness/file_store/in_memory_agent_file_store.dart';

void main() {
  group('FileAccessProvider constructor', () {
    test('null file store throws', () {
      expect(() => FileAccessProvider(null), throwsArgumentError);
    });

    test('with defaults succeeds', () {
      final provider = FileAccessProvider(InMemoryAgentFileStore());

      expect(provider, isNotNull);
    });
  });

  group('FileAccessProvider context', () {
    test('returns tools', () async {
      final tools = await createTools();

      expect(tools, hasLength(5));
      expect(
        tools.whereType<AIFunction>().map((t) => t.name),
        unorderedEquals([
          'FileAccess_SaveFile',
          'FileAccess_ReadFile',
          'FileAccess_DeleteFile',
          'FileAccess_ListFiles',
          'FileAccess_SearchFiles',
        ]),
      );
    });

    test('returns instructions', () async {
      final provider = FileAccessProvider(InMemoryAgentFileStore());

      final result = await provider.invoking(createInvokingContext());

      expect(result.instructions, isNotNull);
      expect(result.instructions, contains('File Access'));
      expect(result.instructions, contains('FileAccess_'));
      expect(
        result.instructions,
        contains('persist beyond the current session'),
      );
    });

    test('does not inject messages', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'Content');
      final provider = FileAccessProvider(store);

      final result = await provider.invoking(createInvokingContext());

      expect(result.messages, isNull);
    });

    test('state keys returns empty', () {
      final provider = FileAccessProvider(InMemoryAgentFileStore());

      expect(provider.stateKeys, isEmpty);
    });
  });

  group('FileAccessProvider save file', () {
    test('creates file', () async {
      final store = InMemoryAgentFileStore();
      final tools = await createTools(store);
      final saveFile = getTool(tools, 'FileAccess_SaveFile');

      await saveFile.invoke(
        AIFunctionArguments({
          'fileName': 'notes.md',
          'content': 'Test content',
        }),
      );

      expect(await store.readFileAsync('notes.md'), 'Test content');
    });

    test('does not create description sidecar', () async {
      final store = InMemoryAgentFileStore();
      final tools = await createTools(store);
      final saveFile = getTool(tools, 'FileAccess_SaveFile');

      await saveFile.invoke(
        AIFunctionArguments({
          'fileName': 'research.md',
          'content': 'Long research content...',
        }),
      );

      expect(
        await store.readFileAsync('research.md'),
        'Long research content...',
      );
      expect(await store.readFileAsync('research_description.md'), isNull);
    });

    test('existing file without overwrite returns error', () async {
      final store = InMemoryAgentFileStore();
      final tools = await createTools(store);
      final saveFile = getTool(tools, 'FileAccess_SaveFile');
      await saveFile.invoke(
        AIFunctionArguments({'fileName': 'notes.md', 'content': 'Original'}),
      );

      final result = await saveFile.invoke(
        AIFunctionArguments({'fileName': 'notes.md', 'content': 'Updated'}),
      );

      expect(await store.readFileAsync('notes.md'), 'Original');
      expect(
        result,
        isA<String>().having((s) => s, 'text', contains('already exists')),
      );
    });

    test('existing file with overwrite succeeds', () async {
      final store = InMemoryAgentFileStore();
      final tools = await createTools(store);
      final saveFile = getTool(tools, 'FileAccess_SaveFile');
      await saveFile.invoke(
        AIFunctionArguments({'fileName': 'notes.md', 'content': 'Original'}),
      );

      await saveFile.invoke(
        AIFunctionArguments({
          'fileName': 'notes.md',
          'content': 'Updated',
          'overwrite': true,
        }),
      );

      expect(await store.readFileAsync('notes.md'), 'Updated');
    });

    test('returns confirmation', () async {
      final tools = await createTools();
      final saveFile = getTool(tools, 'FileAccess_SaveFile');

      final result = await saveFile.invoke(
        AIFunctionArguments({'fileName': 'test.md', 'content': 'Content'}),
      );

      expect(result, isA<String>().having((s) => s, 'text', contains('saved')));
    });
  });

  group('FileAccessProvider read file', () {
    test('existing file returns content', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'Stored content');
      final tools = await createTools(store);
      final readFile = getTool(tools, 'FileAccess_ReadFile');

      final result = await readFile.invoke(
        AIFunctionArguments({'fileName': 'notes.md'}),
      );

      expect(result, 'Stored content');
    });

    test('non-existent returns not found message', () async {
      final tools = await createTools();
      final readFile = getTool(tools, 'FileAccess_ReadFile');

      final result = await readFile.invoke(
        AIFunctionArguments({'fileName': 'nonexistent.md'}),
      );

      expect(
        result,
        isA<String>().having((s) => s, 'text', contains('not found')),
      );
    });
  });

  group('FileAccessProvider delete file', () {
    test('existing file deletes and returns confirmation', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'Content');
      final tools = await createTools(store);
      final deleteFile = getTool(tools, 'FileAccess_DeleteFile');

      final result = await deleteFile.invoke(
        AIFunctionArguments({'fileName': 'notes.md'}),
      );

      expect(
        result,
        isA<String>().having((s) => s, 'text', contains('deleted')),
      );
      expect(await store.fileExistsAsync('notes.md'), isFalse);
    });

    test('non-existent returns not found', () async {
      final tools = await createTools();
      final deleteFile = getTool(tools, 'FileAccess_DeleteFile');

      final result = await deleteFile.invoke(
        AIFunctionArguments({'fileName': 'missing.md'}),
      );

      expect(
        result,
        isA<String>().having((s) => s, 'text', contains('not found')),
      );
    });
  });

  group('FileAccessProvider list files', () {
    test('returns file names', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'Content');
      await store.writeFileAsync('data.txt', 'Data');
      final tools = await createTools(store);
      final listFiles = getTool(tools, 'FileAccess_ListFiles');

      final result = await listFiles.invoke(AIFunctionArguments());

      expect(result, isA<List<String>>());
      expect(result as List<String>, unorderedEquals(['data.txt', 'notes.md']));
    });

    test('does not filter description files', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'Content');
      await store.writeFileAsync('notes_description.md', 'Description');
      final tools = await createTools(store);
      final listFiles = getTool(tools, 'FileAccess_ListFiles');

      final result = await listFiles.invoke(AIFunctionArguments());

      expect(result as List<String>, hasLength(2));
    });

    test('empty store returns empty list', () async {
      final tools = await createTools();
      final listFiles = getTool(tools, 'FileAccess_ListFiles');

      final result = await listFiles.invoke(AIFunctionArguments());

      expect(result as List<String>, isEmpty);
    });
  });

  group('FileAccessProvider search files', () {
    test('finds matching content', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync(
        'notes.md',
        'Important research findings about AI',
      );
      final tools = await createTools(store);
      final searchFiles = getTool(tools, 'FileAccess_SearchFiles');

      final result = await searchFiles.invoke(
        AIFunctionArguments({
          'regexPattern': 'research findings',
          'filePattern': '',
        }),
      );

      final entries = result as List;
      expect(entries, hasLength(1));
      expect(entries[0].fileName, 'notes.md');
      expect(entries[0].matchingLines, isNotEmpty);
    });

    test('with file pattern filters results', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'Important data');
      await store.writeFileAsync('data.txt', 'Important data');
      final tools = await createTools(store);
      final searchFiles = getTool(tools, 'FileAccess_SearchFiles');

      final result = await searchFiles.invoke(
        AIFunctionArguments({
          'regexPattern': 'Important',
          'filePattern': '*.md',
        }),
      );

      final entries = result as List;
      expect(entries, hasLength(1));
      expect(entries[0].fileName, 'notes.md');
    });

    test('no matches returns empty', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'No matching content here');
      final tools = await createTools(store);
      final searchFiles = getTool(tools, 'FileAccess_SearchFiles');

      final result = await searchFiles.invoke(
        AIFunctionArguments({'regexPattern': 'nonexistent pattern xyz'}),
      );

      expect(result as List, isEmpty);
    });
  });

  group('FileAccessProvider path traversal protection', () {
    test('save file path traversal throws', () async {
      final tools = await createTools();
      final saveFile = getTool(tools, 'FileAccess_SaveFile');

      await expectLater(
        saveFile.invoke(
          AIFunctionArguments({
            'fileName': '../escape.md',
            'content': 'Content',
          }),
        ),
        throwsArgumentError,
      );
    });

    test('save file absolute path throws', () async {
      final tools = await createTools();
      final saveFile = getTool(tools, 'FileAccess_SaveFile');

      await expectLater(
        saveFile.invoke(
          AIFunctionArguments({
            'fileName': '/etc/passwd',
            'content': 'Content',
          }),
        ),
        throwsArgumentError,
      );
    });

    test('save file drive-rooted path throws', () async {
      final tools = await createTools();
      final saveFile = getTool(tools, 'FileAccess_SaveFile');

      await expectLater(
        saveFile.invoke(
          AIFunctionArguments({
            'fileName': r'C:\temp\file.md',
            'content': 'Content',
          }),
        ),
        throwsArgumentError,
      );
    });

    test('save file double dots in file name allowed', () async {
      final store = InMemoryAgentFileStore();
      final tools = await createTools(store);
      final saveFile = getTool(tools, 'FileAccess_SaveFile');

      await saveFile.invoke(
        AIFunctionArguments({'fileName': 'notes..md', 'content': 'Content'}),
      );

      expect(await store.readFileAsync('notes..md'), 'Content');
    });

    test('read file path traversal throws', () async {
      final tools = await createTools();
      final readFile = getTool(tools, 'FileAccess_ReadFile');

      await expectLater(
        readFile.invoke(AIFunctionArguments({'fileName': '../../etc/passwd'})),
        throwsArgumentError,
      );
    });

    test('delete file path traversal throws', () async {
      final tools = await createTools();
      final deleteFile = getTool(tools, 'FileAccess_DeleteFile');

      await expectLater(
        deleteFile.invoke(AIFunctionArguments({'fileName': '../escape.md'})),
        throwsArgumentError,
      );
    });
  });

  group('FileAccessProvider options', () {
    test('custom instructions override default', () async {
      final provider = FileAccessProvider(
        InMemoryAgentFileStore(),
        options: FileAccessProviderOptions()
          ..instructions = 'Custom file access instructions.',
      );

      final result = await provider.invoking(createInvokingContext());

      expect(result.instructions, 'Custom file access instructions.');
    });

    test('null options uses default instructions', () async {
      final provider = FileAccessProvider(InMemoryAgentFileStore());

      final result = await provider.invoking(createInvokingContext());

      expect(result.instructions, contains('File Access'));
    });
  });
}

Future<Iterable<AITool>> createTools([InMemoryAgentFileStore? store]) async {
  final provider = FileAccessProvider(store ?? InMemoryAgentFileStore());
  final result = await provider.invoking(createInvokingContext());
  return result.tools!;
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

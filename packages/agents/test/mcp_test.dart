import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/ai/skills/agent_skills_source_context.dart';
import 'package:agents/src/mcp/agent_mcp_skills_source.dart';
import 'package:agents/src/mcp/agent_mcp_skills_source_options.dart';
import 'package:agents/src/mcp/mcp_client_task_extensions.dart';
import 'package:agents/src/mcp/mcp_task_options.dart';
import 'package:archive/archive.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp;
import 'package:test/test.dart';

void main() {
  group('McpClientTaskExtensions', () {
    test(
      'maps direct tools to AIFunction and returns MCP result JSON',
      () async {
        final client = _FakeMcpClient()
          ..tools = [_tool('echo')]
          ..directResult = _toolResult({'ok': true});

        final tools = await client.listAgentToolsWithTaskSupport();
        final result = await tools.single.invoke(
          AIFunctionArguments({'value': 'hello'}),
        );

        expect(tools.single, isA<McpClientAIFunction>());
        expect(result, {
          'content': [
            {'type': 'text', 'text': '{"ok":true}'},
          ],
          'structuredContent': {'ok': true},
        });
        expect(client.directCalls.single.arguments, {'value': 'hello'});
      },
    );

    test('wraps required task tools and returns final task result', () async {
      final client = _FakeMcpClient()
        ..tools = [_tool('slow', taskSupport: 'required')]
        ..createdTask = _task(
          't1',
          status: mcp.TaskStatus.working,
          pollInterval: 1,
        )
        ..taskStatuses = [_task('t1', status: mcp.TaskStatus.completed)]
        ..taskResult = _toolResult({'done': true});

      final tools = await client.listAgentToolsWithTaskSupport(
        taskOptions: McpTaskOptions(
          defaultTimeToLive: const Duration(seconds: 5),
        ),
      );
      final result = await tools.single.invoke(AIFunctionArguments());

      expect(tools.single, isA<TaskAwareMcpClientAIFunction>());
      expect(client.rawToolCallParams.single['task'], {'ttl': 5000});
      expect(result, containsPair('structuredContent', {'done': true}));
    });

    test('failed and cancelled tasks surface as errors', () async {
      final failed = _FakeMcpClient()
        ..createdTask = _task(
          't1',
          status: mcp.TaskStatus.working,
          pollInterval: 1,
        )
        ..taskStatuses = [
          _task('t1', status: mcp.TaskStatus.failed, message: 'bad'),
        ];
      final failedFunction = TaskAwareMcpClientAIFunction(
        client: failed,
        tool: _tool('slow', taskSupport: 'required'),
      );
      await expectLater(
        failedFunction.invoke(AIFunctionArguments()),
        throwsA(isA<StateError>()),
      );

      final cancelled = _FakeMcpClient()
        ..createdTask = _task(
          't2',
          status: mcp.TaskStatus.working,
          pollInterval: 1,
        )
        ..taskStatuses = [_task('t2', status: mcp.TaskStatus.cancelled)];
      final cancelledFunction = TaskAwareMcpClientAIFunction(
        client: cancelled,
        tool: _tool('slow', taskSupport: 'required'),
      );
      await expectLater(
        cancelledFunction.invoke(AIFunctionArguments()),
        throwsA(isA<OperationCanceledException>()),
      );
    });

    test('local cancellation best-effort cancels remote task', () async {
      final client = _FakeMcpClient()
        ..createdTask = _task(
          't1',
          status: mcp.TaskStatus.working,
          pollInterval: 10000,
        );
      final function = TaskAwareMcpClientAIFunction(
        client: client,
        tool: _tool('slow', taskSupport: 'required'),
      );
      final source = CancellationTokenSource();

      final invocation = function.invoke(
        AIFunctionArguments(),
        cancellationToken: source.token,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      source.cancel();

      await expectLater(invocation, throwsA(isA<OperationCanceledException>()));
      expect(client.cancelledTaskIds, ['t1']);
    });

    test(
      'method-not-found task augmentation falls back to direct call',
      () async {
        final client = _FakeMcpClient()
          ..taskCallThrowsMethodNotFound = true
          ..directResult = _toolResult({'fallback': true});
        final function = TaskAwareMcpClientAIFunction(
          client: client,
          tool: _tool('slow', taskSupport: 'required'),
        );

        final result = await function.invoke(AIFunctionArguments());

        expect(result, containsPair('structuredContent', {'fallback': true}));
        expect(client.directCalls, hasLength(1));
      },
    );
  });

  group('AgentMcpSkillsSource', () {
    test(
      'returns empty for missing empty malformed and unsupported indexes',
      () async {
        final missing = _FakeMcpClient();
        expect(
          await AgentMcpSkillsSource(missing).getSkills(_skillsContext),
          isEmpty,
        );

        final empty = _FakeMcpClient()
          ..resources[AgentMcpSkillsSource.indexUri] = _textResource('');
        expect(
          await AgentMcpSkillsSource(empty).getSkills(_skillsContext),
          isEmpty,
        );

        final malformed = _FakeMcpClient()
          ..resources[AgentMcpSkillsSource.indexUri] = _textResource('{nope');
        expect(
          await AgentMcpSkillsSource(malformed).getSkills(_skillsContext),
          isEmpty,
        );

        final unsupported = _FakeMcpClient()
          ..resources[AgentMcpSkillsSource.indexUri] = _textResource(
            jsonEncode({
              'skills': [
                {
                  'name': 'dynamic',
                  'type': 'mcp-resource-template',
                  'description': 'Dynamic',
                  'url': 'skill://dynamic/{id}/SKILL.md',
                },
              ],
            }),
          );
        expect(
          await AgentMcpSkillsSource(unsupported).getSkills(_skillsContext),
          isEmpty,
        );
      },
    );

    test('loads skill-md content and resolves sibling resources', () async {
      final client = _FakeMcpClient()
        ..resources[AgentMcpSkillsSource.indexUri] = _textResource(
          jsonEncode({
            'skills': [
              {
                'name': 'remote-skill',
                'type': 'skill-md',
                'description': 'Remote skill',
                'url': 'skill://remote-skill/SKILL.md',
              },
            ],
          }),
        )
        ..resources['skill://remote-skill/SKILL.md'] = _textResource(
          'Use remote skill.',
        )
        ..resources['skill://remote-skill/references/guide.md'] = _textResource(
          'guide',
        );

      final skill = (await AgentMcpSkillsSource(
        client,
      ).getSkills(_skillsContext)).single;

      expect(skill.frontmatter.name, 'remote-skill');
      expect(await skill.getContent(), 'Use remote skill.');
      final resource = await skill.getResource('references/guide.md');
      expect(await resource!.read(), 'guide');
    });

    test('uses refresh interval cache', () async {
      final client = _FakeMcpClient()
        ..resources[AgentMcpSkillsSource.indexUri] = _textResource(
          jsonEncode({
            'skills': [
              {
                'name': 'cached-skill',
                'type': 'skill-md',
                'description': 'Cached skill',
                'url': 'skill://cached-skill/SKILL.md',
              },
            ],
          }),
        );
      final source = AgentMcpSkillsSource(
        client,
        options: AgentMcpSkillsSourceOptions(
          refreshInterval: const Duration(minutes: 1),
        ),
      );

      await source.getSkills(_skillsContext);
      await source.getSkills(_skillsContext);

      expect(client.resourceReadCount[AgentMcpSkillsSource.indexUri], 1);
    });

    test('extracts archive skill and prunes stale directories', () async {
      final root = await Directory.systemTemp.createTemp('mcp_skills_test_');
      addTearDown(() => root.deleteSync(recursive: true));
      final archiveUri = 'skill://zip-skill/archive.zip';
      final client = _FakeMcpClient();
      final source = AgentMcpSkillsSource(
        client,
        options: AgentMcpSkillsSourceOptions(archiveSkillsDirectory: root.path),
      );

      client.resources[AgentMcpSkillsSource.indexUri] = _textResource(
        jsonEncode({
          'skills': [
            {
              'name': 'zip-skill',
              'type': 'archive',
              'description': 'Zip skill',
              'url': archiveUri,
            },
          ],
        }),
      );
      client.resources[archiveUri] = _blobResource(_zipSkillArchive());

      final skills = await source.getSkills(_skillsContext);

      expect(skills.single.frontmatter.name, 'zip-skill');
      expect(await skills.single.getResource('references/guide.md'), isNotNull);
      expect(Directory('${root.path}/zip-skill').existsSync(), isTrue);

      client.resources[AgentMcpSkillsSource.indexUri] = _textResource(
        jsonEncode({'skills': <Object>[]}),
      );
      expect(await source.getSkills(_skillsContext), isEmpty);
      expect(Directory('${root.path}/zip-skill').existsSync(), isFalse);
    });

    test('skips archives that exceed extraction limits', () async {
      final root = await Directory.systemTemp.createTemp(
        'mcp_skills_limit_test_',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      const archiveUri = 'skill://limit-skill/archive.zip';
      final client = _FakeMcpClient()
        ..resources[AgentMcpSkillsSource.indexUri] = _textResource(
          jsonEncode({
            'skills': [
              {
                'name': 'limit-skill',
                'type': 'archive',
                'description': 'Limit skill',
                'url': archiveUri,
              },
            ],
          }),
        )
        ..resources[archiveUri] = _blobResource(_zipSkillArchive());

      final skills = await AgentMcpSkillsSource(
        client,
        options: AgentMcpSkillsSourceOptions(
          archiveSkillsDirectory: root.path,
          archiveMaxFileCount: 1,
        ),
      ).getSkills(_skillsContext);

      expect(skills, isEmpty);
      expect(Directory('${root.path}/limit-skill').existsSync(), isFalse);
    });
  });
}

class _FakeMcpClient extends mcp.McpClient {
  _FakeMcpClient()
    : super(const mcp.Implementation(name: 'fake', version: '1.0.0'));

  List<mcp.Tool> tools = const [];
  mcp.CallToolResult directResult = _toolResult({'direct': true});
  mcp.Task? createdTask;
  List<mcp.Task> taskStatuses = [];
  mcp.CallToolResult taskResult = _toolResult({'task': true});
  bool taskCallThrowsMethodNotFound = false;
  final directCalls = <mcp.CallToolRequest>[];
  final rawToolCallParams = <Map<String, dynamic>>[];
  final cancelledTaskIds = <String>[];
  final resources = <String, mcp.ReadResourceResult>{};
  final resourceReadCount = <String, int>{};

  @override
  Future<mcp.ListToolsResult> listTools({
    mcp.ListToolsRequest? params,
    mcp.RequestOptions? options,
  }) async {
    return mcp.ListToolsResult(tools: tools);
  }

  @override
  Future<mcp.CallToolResult> callTool(
    mcp.CallToolRequest params, {
    mcp.RequestOptions? options,
  }) async {
    directCalls.add(params);
    return directResult;
  }

  @override
  void assertTaskCapability(String method) {}

  @override
  Future<mcp.ReadResourceResult> readResource(
    mcp.ReadResourceRequest params, [
    mcp.RequestOptions? options,
  ]) async {
    resourceReadCount[params.uri] = (resourceReadCount[params.uri] ?? 0) + 1;
    final result = resources[params.uri];
    if (result == null) {
      throw mcp.McpError(
        mcp.ErrorCode.invalidRequest.value,
        'missing resource',
      );
    }
    return result;
  }

  @override
  Future<T> request<T extends mcp.BaseResultData>(
    mcp.JsonRpcRequest requestData,
    T Function(Map<String, dynamic> resultJson) resultFactory, [
    mcp.RequestOptions? options,
    int? relatedRequestId,
  ]) async {
    switch (requestData.method) {
      case mcp.Method.toolsCall:
        rawToolCallParams.add(requestData.params ?? const {});
        if (taskCallThrowsMethodNotFound) {
          throw mcp.McpError(
            mcp.ErrorCode.methodNotFound.value,
            'no task augmentation',
          );
        }
        return resultFactory({
          'task': (createdTask ?? _task('t1')).toBareJson(),
        });
      case mcp.Method.tasksGet:
        return resultFactory(
          (taskStatuses.isEmpty
                  ? _task('t1', status: mcp.TaskStatus.completed)
                  : taskStatuses.removeAt(0))
              .toJson(),
        );
      case mcp.Method.tasksResult:
        return resultFactory(taskResult.toJson());
      case mcp.Method.tasksCancel:
        final taskId = requestData.params?['taskId'] as String;
        cancelledTaskIds.add(taskId);
        return resultFactory(
          _task(taskId, status: mcp.TaskStatus.cancelled).toJson(),
        );
      default:
        throw UnsupportedError('Unexpected request: ${requestData.method}');
    }
  }
}

mcp.Tool _tool(String name, {String taskSupport = 'forbidden'}) {
  return mcp.Tool(
    name: name,
    description: 'Tool $name',
    inputSchema: const mcp.JsonObject(properties: {'value': mcp.JsonString()}),
    outputSchema: const mcp.JsonObject(),
    execution: mcp.ToolExecution(taskSupport: taskSupport),
  );
}

mcp.CallToolResult _toolResult(Map<String, dynamic> value) {
  return mcp.CallToolResult.fromStructuredContent(value);
}

mcp.Task _task(
  String id, {
  mcp.TaskStatus status = mcp.TaskStatus.working,
  String? message,
  int? pollInterval,
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return mcp.Task(
    taskId: id,
    status: status,
    statusMessage: message,
    ttl: null,
    pollInterval: pollInterval,
    createdAt: now,
    lastUpdatedAt: now,
  );
}

mcp.ReadResourceResult _textResource(String text) {
  return mcp.ReadResourceResult(
    contents: [mcp.TextResourceContents(uri: 'test://resource', text: text)],
  );
}

mcp.ReadResourceResult _blobResource(List<int> bytes) {
  return mcp.ReadResourceResult(
    contents: [
      mcp.BlobResourceContents(
        uri: 'test://resource',
        mimeType: 'application/zip',
        blob: base64Encode(bytes),
      ),
    ],
  );
}

List<int> _zipSkillArchive() {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string('zip-skill/SKILL.md', '''
---
name: zip-skill
description: Zip skill
---
Use zip skill.
'''),
    )
    ..addFile(ArchiveFile.string('zip-skill/references/guide.md', 'guide'));
  return ZipEncoder().encodeBytes(archive);
}

final _skillsContext = AgentSkillsSourceContext(_FakeAgent(), null);

class _FakeSession extends AgentSession {
  _FakeSession() : super(AgentSessionStateBag(null));
}

class _FakeAgent extends AIAgent {
  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _FakeSession();

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _FakeSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    // ignore: non_constant_identifier_names
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

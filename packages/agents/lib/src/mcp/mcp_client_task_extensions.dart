import 'dart:async';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp;

import 'mcp_task_options.dart';

/// Extensions for exposing MCP tools as `extensions` AI functions.
extension McpClientTaskExtensions on mcp.McpClient {
  /// Lists all MCP tools and adapts them to [AIFunction] instances.
  ///
  /// Tools whose MCP `execution.taskSupport` value is `required` are invoked
  /// through MCP task augmentation. Other tools are invoked directly.
  Future<List<AIFunction>> listAgentToolsWithTaskSupport({
    McpTaskOptions? taskOptions,
    mcp.RequestOptions? requestOptions,
  }) async {
    final tools = <mcp.Tool>[];
    String? cursor;
    do {
      final result = await listTools(
        params: cursor == null ? null : mcp.ListToolsRequest(cursor: cursor),
        options: requestOptions,
      );
      tools.addAll(result.tools);
      cursor = result.nextCursor;
    } while (cursor != null);

    return [
      for (final tool in tools)
        tool.execution?.taskSupport == 'required'
            ? TaskAwareMcpClientAIFunction(
                client: this,
                tool: tool,
                options: taskOptions ?? McpTaskOptions(),
              )
            : McpClientAIFunction(client: this, tool: tool),
    ];
  }
}

/// An [AIFunction] backed by an MCP tool.
class McpClientAIFunction extends AIFunction {
  /// Creates a direct MCP tool function.
  McpClientAIFunction({required this.client, required this.tool})
    : super(
        name: tool.name,
        description: tool.description ?? tool.title,
        parametersSchema: _schemaToMap(tool.inputSchema),
        returnSchema: tool.outputSchema == null
            ? null
            : _schemaToMap(tool.outputSchema!),
      );

  /// The MCP client used to invoke the tool.
  final mcp.McpClient client;

  /// The MCP tool declaration.
  final mcp.Tool tool;

  @override
  Future<Object?> invokeCore(
    AIFunctionArguments arguments, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final result = await client.callTool(
      mcp.CallToolRequest(name: name, arguments: _argumentsToMap(arguments)),
    );
    cancellationToken?.throwIfCancellationRequested();
    return result.toJson();
  }
}

/// An MCP tool function that must be invoked through task augmentation.
class TaskAwareMcpClientAIFunction extends McpClientAIFunction {
  /// Creates a task-aware MCP tool function.
  TaskAwareMcpClientAIFunction({
    required super.client,
    required super.tool,
    McpTaskOptions? options,
  }) : options = options ?? McpTaskOptions();

  /// Options used for task-based calls.
  final McpTaskOptions options;

  @override
  Future<Object?> invokeCore(
    AIFunctionArguments arguments, {
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none;
    token.throwIfCancellationRequested();

    try {
      final result = await _callToolWithTask(
        _argumentsToMap(arguments),
        cancellationToken: token,
      );
      return result.toJson();
    } on mcp.McpError catch (error) {
      if (error.code == mcp.ErrorCode.methodNotFound.value) {
        final result = await client.callTool(
          mcp.CallToolRequest(
            name: name,
            arguments: _argumentsToMap(arguments),
          ),
        );
        return result.toJson();
      }
      rethrow;
    }
  }

  Future<mcp.CallToolResult> _callToolWithTask(
    Map<String, dynamic> arguments, {
    required CancellationToken cancellationToken,
  }) async {
    client.assertTaskCapability(mcp.Method.toolsCall);

    String? taskId;
    CancellationTokenRegistration? registration;
    if (options.cancelRemoteTaskOnLocalCancellation &&
        cancellationToken.canBeCanceled) {
      registration = cancellationToken.register((_) {
        final id = taskId;
        if (id != null) {
          unawaited(_cancelRemoteTask(id));
        }
      });
    }

    try {
      final callRequest = mcp.CallToolRequest(
        name: name,
        arguments: arguments,
      ).toJson();
      final ttl = options.defaultTimeToLive;
      final response = await client.request<_RawMcpResult>(
        mcp.JsonRpcCallToolRequest(
          id: -1,
          params: {
            ...callRequest,
            'task': {if (ttl != null) 'ttl': ttl.inMilliseconds},
          },
        ),
        (json) => _RawMcpResult(json, meta: json['_meta']),
      );
      cancellationToken.throwIfCancellationRequested();

      final data = response.data;
      if (!data.containsKey('task')) {
        return mcp.CallToolResult.fromJson(data);
      }

      final taskResult = mcp.CreateTaskResult.fromJson(data);
      var task = taskResult.task;
      taskId = task.taskId;

      while (!task.status.isTerminal) {
        await _delayWithCancellation(
          Duration(milliseconds: task.pollInterval ?? 1000),
          cancellationToken,
        );
        task = await _getTask(task.taskId);
        cancellationToken.throwIfCancellationRequested();

        if (task.status == mcp.TaskStatus.inputRequired) {
          return await _getTaskResult(task.taskId);
        }
      }

      return switch (task.status) {
        mcp.TaskStatus.completed => await _getTaskResult(task.taskId),
        mcp.TaskStatus.cancelled => throw OperationCanceledException(
          message: task.statusMessage ?? 'The MCP task was cancelled.',
          cancellationToken: cancellationToken,
        ),
        mcp.TaskStatus.failed => throw StateError(
          task.statusMessage ?? 'The MCP task failed.',
        ),
        _ => throw StateError('Unhandled MCP task status: ${task.status.name}'),
      };
    } finally {
      registration?.dispose();
    }
  }

  Future<mcp.Task> _getTask(String taskId) {
    return client.request<mcp.Task>(
      mcp.JsonRpcGetTaskRequest(
        id: -1,
        getParams: mcp.GetTaskRequest(taskId: taskId),
      ),
      (json) => mcp.Task.fromJson(json),
    );
  }

  Future<mcp.CallToolResult> _getTaskResult(String taskId) {
    return client.request<mcp.CallToolResult>(
      mcp.JsonRpcTaskResultRequest(
        id: -1,
        resultParams: mcp.TaskResultRequest(taskId: taskId),
      ),
      (json) => mcp.CallToolResult.fromJson(json),
    );
  }

  Future<void> _cancelRemoteTask(String taskId) async {
    try {
      await client.request<mcp.Task>(
        mcp.JsonRpcCancelTaskRequest(
          id: -1,
          cancelParams: mcp.CancelTaskRequest(taskId: taskId),
        ),
        (json) => mcp.Task.fromJson(json),
      );
    } catch (_) {
      // Best effort only: local cancellation must retain its original meaning.
    }
  }
}

class _RawMcpResult implements mcp.BaseResultData {
  _RawMcpResult(this.data, {this.meta});

  final Map<String, dynamic> data;

  @override
  final Map<String, dynamic>? meta;

  @override
  Map<String, dynamic> toJson() => {...data, if (meta != null) '_meta': meta};
}

Map<String, dynamic> _schemaToMap(mcp.JsonSchema schema) =>
    Map<String, dynamic>.from(schema.toJson());

Map<String, dynamic> _argumentsToMap(AIFunctionArguments arguments) =>
    Map<String, dynamic>.from(arguments);

Future<void> _delayWithCancellation(
  Duration duration,
  CancellationToken cancellationToken,
) {
  cancellationToken.throwIfCancellationRequested();
  if (!cancellationToken.canBeCanceled) {
    return Future<void>.delayed(duration);
  }

  final completer = Completer<void>();
  Timer? timer;
  CancellationTokenRegistration? registration;

  void completeOnce(void Function() complete) {
    if (completer.isCompleted) {
      return;
    }
    timer?.cancel();
    registration?.dispose();
    complete();
  }

  timer = Timer(duration, () => completeOnce(completer.complete));
  registration = cancellationToken.register((_) {
    completeOnce(
      () => completer.completeError(
        OperationCanceledException(cancellationToken: cancellationToken),
      ),
    );
  });
  return completer.future;
}

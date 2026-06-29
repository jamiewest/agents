/// Options that control task-augmented MCP tool invocation.
class McpTaskOptions {
  /// Creates task invocation options.
  McpTaskOptions({
    this.defaultTimeToLive,
    this.cancelRemoteTaskOnLocalCancellation = true,
  });

  /// Default task time-to-live sent as `task.ttl`, when set.
  final Duration? defaultTimeToLive;

  /// Whether local cancellation should best-effort cancel the remote MCP task.
  final bool cancelRemoteTaskOnLocalCancellation;
}

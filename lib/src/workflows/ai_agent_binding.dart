import '../abstractions/agent_run_options.dart';
import '../abstractions/agent_session.dart';
import '../abstractions/ai_agent.dart';
import 'chat_protocol_executor.dart';
import 'executor_binding.dart';
import 'executor_options.dart';
import 'protocol_descriptor.dart';

/// Binds an [AIAgent] into a workflow as a chat protocol executor.
class AIAgentBinding implements ExecutorBinding {
  /// Creates a binding for [agent].
  AIAgentBinding(
    this.agent, {
    String? id,
    this.session,
    this.runOptions,
    ExecutorOptions? options,
  }) : id = id ?? agent.name ?? agent.id,
       options = options ?? const ExecutorOptions();

  /// Gets the agent represented by this binding.
  final AIAgent agent;

  /// Gets or sets the session reused by the created executor.
  AgentSession? session;

  /// Gets the run options supplied to each agent invocation.
  final AgentRunOptions? runOptions;

  /// Gets executor options.
  final ExecutorOptions options;

  @override
  final String id;

  @override
  bool get isPlaceholder => false;

  @override
  bool get isSharedInstance => false;

  @override
  bool get supportsConcurrentSharedExecution => true;

  @override
  bool get supportsResetting => false;

  @override
  Future<ChatProtocolExecutor> createInstance() async => ChatProtocolExecutor(
    agent,
    id: id,
    session: session,
    runOptions: runOptions,
    options: options,
  );

  @override
  Future<ProtocolDescriptor> describeProtocol() async =>
      (await createInstance()).protocol;

  @override
  Future<bool> tryReset() async => false;
}

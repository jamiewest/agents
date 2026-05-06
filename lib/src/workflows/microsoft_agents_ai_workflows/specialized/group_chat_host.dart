import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../../func_typedefs.dart';
import '../chat_protocol_executor.dart';
import '../executor_binding.dart';
import '../group_chat_manager.dart';
import '../protocol_builder.dart';
import '../resettable_executor.dart';
import '../turn_token.dart';
import '../workflow_context.dart';

class GroupChatHost extends ChatProtocolExecutor implements ResettableExecutor {
  GroupChatHost(
    String id,
    List<AIAgent> agents,
    Map<AIAgent, ExecutorBinding> agentMap,
    Func<List<AIAgent>, GroupChatManager> managerFactory,
  ) :
      _agents = agents,
      _agentMap = agentMap,
      _managerFactory = managerFactory;

  static final ChatProtocolExecutorOptions s_options;

  final List<AIAgent> _agents = agents;

  final Map<AIAgent, ExecutorBinding> _agentMap = agentMap;

  final Func<List<AIAgent>, GroupChatManager> _managerFactory = managerFactory;

  late GroupChatManager? _manager;

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    return super.configureProtocol(protocolBuilder).yieldsOutput<List<ChatMessage>>();
  }

  @override
  Future takeTurn(
    List<ChatMessage> messages,
    WorkflowContext context,
    bool? emitEvents,
    {CancellationToken? cancellationToken, }
  ) async {
    this._manager ??= this._managerFactory(this._agents);
    if (!await this._manager.shouldTerminateAsync(messages, cancellationToken)) {
      var filtered = await this._manager.updateHistoryAsync(
        messages,
        cancellationToken,
      ) ;
      messages = filtered == null || identical(filtered, messages) ? messages : [...filtered];
      var executor;
      if (await this._manager.selectNextAgentAsync(messages, cancellationToken) is AIAgent &&
                this._agentMap.containsKey(nextAgent)) {
        this._manager.iterationCount++;
        await context.sendMessage(
          messages,
          executor.id,
          cancellationToken,
        ) ;
        await context.sendMessage(
          turnToken(emitEvents),
          executor.id,
          cancellationToken,
        ) ;
        return;
      }
    }
    this._manager = null;
    await context.yieldOutput(messages, cancellationToken);
  }

  @override
  Future resetAsync() {
    this._manager = null;
    return super.resetAsync();
  }

  Future resetAsync() {
    return this.resetAsync();
  }
}

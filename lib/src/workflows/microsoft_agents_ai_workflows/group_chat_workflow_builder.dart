import 'package:extensions/ai.dart';
import '../../func_typedefs.dart';
import 'group_chat_manager.dart';
import 'specialized/group_chat_host.dart';
import 'workflow.dart';

/// Provides a builder for specifying group chat relationships between agents
/// and building the resulting workflow.
class GroupChatWorkflowBuilder {
  GroupChatWorkflowBuilder(Func<List<AIAgent>, GroupChatManager> managerFactory) : _managerFactory = managerFactory;

  final Func<List<AIAgent>, GroupChatManager> _managerFactory;

  final Set<AIAgent> _participants = new(AIAgentIDEqualityComparer.Instance);

  String _name = '';

  String _description = '';

  /// Adds the specified `agents` as participants to the group chat workflow.
  ///
  /// Returns: This instance of the [GroupChatWorkflowBuilder].
  ///
  /// [agents] The agents to add as participants.
  GroupChatWorkflowBuilder addParticipants(Iterable<AIAgent> agents) {
    for (final agent in agents) {
      if (agent == null) {
        throw ArgumentError.notNull("'$1'");
      }
      this._participants.add(agent);
    }
    return this;
  }

  /// Sets the human-readable name for the workflow.
  ///
  /// Returns: This instance of the [GroupChatWorkflowBuilder].
  ///
  /// [name] The name of the workflow.
  GroupChatWorkflowBuilder withName(String name) {
    this._name = name;
    return this;
  }

  /// Sets the description for the workflow.
  ///
  /// Returns: This instance of the [GroupChatWorkflowBuilder].
  ///
  /// [description] The description of what the workflow does.
  GroupChatWorkflowBuilder withDescription(String description) {
    this._description = description;
    return this;
  }

  /// Builds a [Workflow] composed of agents that operate via group chat, with
  /// the next agent to process messages selected by the group chat manager.
  ///
  /// Returns: The workflow built based on the group chat in the builder.
  Workflow build() {
    var agents = this._participants.toList();
    var options = new()
        {
            ReassignOtherAgentsAsUsers = true,
            ForwardIncomingMessages = true
        };
    var agentMap = agents.toDictionary((a) => a, (a) => a.bindAsExecutor(options));
    var groupChatHostFactory = (
      id,
      sessionId,
    ) => new(groupChatHost(id, agents, agentMap, this._managerFactory));
    var host = groupChatHostFactory.bindExecutor('GroupChatHost');
    var builder = new(host);
    if (!(this._name == null || this._name.isEmpty)) {
      builder = builder.withName(this._name);
    }
    if (!(this._description == null || this._description.isEmpty)) {
      builder = builder.withDescription(this._description);
    }
    for (final participant in agentMap.values) {
      builder
                .addEdge(host, participant)
                .addEdge(participant, host);
    }
    return builder.withOutputFrom(host).build();
  }
}

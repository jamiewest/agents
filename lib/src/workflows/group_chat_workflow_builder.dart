import '../abstractions/ai_agent.dart';
import 'executor_instance_binding.dart';
import 'group_chat_manager.dart';
import 'specialized/group_chat_host.dart';
import 'workflow.dart';
import 'workflow_builder.dart';

/// Provides a builder for specifying group chat relationships between agents.
class GroupChatWorkflowBuilder {
  /// Creates a group chat workflow builder.
  GroupChatWorkflowBuilder(this.managerFactory);

  /// Function that creates the [GroupChatManager] for a workflow instance.
  final GroupChatManager Function(List<AIAgent> agents) managerFactory;

  final Map<String, AIAgent> _participants = <String, AIAgent>{};
  String? _name;
  String? _description;

  /// Adds the specified [agents] as participants to the group chat workflow.
  GroupChatWorkflowBuilder addParticipants(Iterable<AIAgent> agents) {
    for (final agent in agents) {
      _participants[agent.id] = agent;
    }
    return this;
  }

  /// Sets the human-readable name for the workflow.
  GroupChatWorkflowBuilder withName(String name) {
    _name = name;
    return this;
  }

  /// Sets the description for the workflow.
  GroupChatWorkflowBuilder withDescription(String description) {
    _description = description;
    return this;
  }

  /// Builds a [Workflow] composed of agents that operate via group chat.
  Workflow build() {
    final agents = _participants.values.toList();
    final host = GroupChatHost('GroupChatHost', agents, managerFactory);
    final builder = WorkflowBuilder(
      ExecutorInstanceBinding(host),
    ).addOutput(host.id).withName(_name).withDescription(_description);
    return builder.build();
  }
}

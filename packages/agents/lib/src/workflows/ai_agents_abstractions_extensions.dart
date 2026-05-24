import '../abstractions/ai_agent.dart';
import 'workflow.dart';
import 'workflow_execution_environment.dart';
import 'workflow_host_agent.dart';

/// Extensions for exposing workflows through the AI agent abstractions.
extension AIWorkflowAbstractionsExtensions on Workflow {
  /// Creates an [AIAgent] that executes this workflow.
  AIAgent asAIAgent({
    WorkflowExecutionEnvironment? executionEnvironment,
    String? name,
    String? description,
  }) => WorkflowHostAgent(
    this,
    executionEnvironment: executionEnvironment,
    name: name,
    description: description,
  );
}

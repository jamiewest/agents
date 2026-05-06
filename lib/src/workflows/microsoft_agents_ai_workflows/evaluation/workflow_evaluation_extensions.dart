import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../../ai/microsoft_agents_ai/evaluation/agent_evaluation_results.dart';
import '../../../ai/microsoft_agents_ai/evaluation/agent_evaluator.dart';
import '../../../ai/microsoft_agents_ai/evaluation/conversation_splitter.dart';
import '../../../ai/microsoft_agents_ai/evaluation/eval_item.dart';
import '../agent_response_event.dart';
import '../executor_invoked_event.dart';
import '../run.dart';

/// Extension methods for evaluating workflow runs.
extension WorkflowEvaluationExtensions on Run {
  /// Evaluates a completed workflow run.
///
/// Returns: Evaluation results with optional per-agent sub-results.
///
/// [run] The completed workflow run.
///
/// [evaluator] The evaluator to score results.
///
/// [includeOverall] Whether to include an overall evaluation.
///
/// [includePerAgent] Whether to include per-agent breakdowns.
///
/// [evalName] Display name for this evaluation run.
///
/// [splitter] Optional conversation splitter to apply to all items. Use
/// [LastTurn], [Full], or a custom [ConversationSplitter] implementation.
///
/// [cancellationToken] Cancellation token.
Future<AgentEvaluationResults> evaluate(
  AgentEvaluator evaluator,
  {bool? includeOverall, bool? includePerAgent, String? evalName, ConversationSplitter? splitter, CancellationToken? cancellationToken, }
) async {
var events = run.outgoingEvents.toList();
var agentData = extractAgentData(events, splitter);
var overallItems = List<EvalItem>();
if (includeOverall) {
  var finalResponse = events.ofType<AgentResponseEvent>().lastOrDefault();
  if (finalResponse != null) {
    var firstInvoked = events.ofType<ExecutorInvokedEvent>().firstOrDefault();
    var query = firstInvoked?.data switch
                {
                    ChatMessage (cm) => cm.text ?? '',
                    List<ChatMessage> (msgs) => msgs.lastOrDefault((m) => m.role == ChatRole.user)?.text ?? '',
                    String (s) => s,
                    (_) => firstInvoked?.data?.toString() ?? '',
                };
    var conversation = List<ChatMessage>();
    conversation.addAll(finalResponse.response.messages);
    overallItems.add(evalItem(query, finalResponse.response.text, conversation));
  }
}
var overallResult = overallItems.length > 0
            ? await evaluator.evaluateAsync(
              overallItems,
              evalName,
              cancellationToken,
            ) 
            : agentEvaluationResults(evaluator.name, <EvaluationResult>[]);
if (includePerAgent && agentData.length > 0) {
  var subResults = new Dictionary<String, AgentEvaluationResults>();
  for (final kvp in agentData) {
    subResults[kvp.key] = await evaluator.evaluateAsync(
                    kvp.value,
                    '${evalName} - ${kvp.key}',
                    cancellationToken);
  }

  overallResult.subResults = subResults;
}
return overallResult;
 }
 }

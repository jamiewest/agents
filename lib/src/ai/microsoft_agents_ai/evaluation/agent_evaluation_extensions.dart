import '../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import 'agent_evaluation_results.dart';
import 'agent_evaluator.dart';
import 'conversation_splitter.dart';
import 'expected_tool_call.dart';

/// Extension methods for evaluating agents, responses, and workflow runs.
extension AgentEvaluationExtensions on AIAgent {
  /// Evaluates an agent by running it against test queries and scoring the
  /// responses.
  ///
  /// Returns: Evaluation results.
  ///
  /// [agent] The agent to evaluate.
  ///
  /// [queries] Test queries to send to the agent.
  ///
  /// [evaluator] The evaluator to score responses.
  ///
  /// [evalName] Display name for this evaluation run.
  ///
  /// [expectedOutput] Optional ground-truth expected outputs, one per query.
  /// When provided, must be the same length as `queries`. Each value is stamped
  /// on the corresponding [ExpectedOutput].
  ///
  /// [expectedToolCalls] Optional expected tool calls, one list per query. When
  /// provided, must be the same length as `queries`. Each list is stamped on
  /// the corresponding [ExpectedToolCalls].
  ///
  /// [splitter] Optional conversation splitter to apply to all items. Use
  /// [LastTurn], [Full], or a custom [ConversationSplitter] implementation.
  ///
  /// [numRepetitions] Number of times to run each query (default 1). When
  /// greater than 1, each query is invoked independently N times to measure
  /// consistency. Results contain all N × queries.Count items.
  ///
  /// [cancellationToken] Cancellation token.
  Future<AgentEvaluationResults> evaluate(
    Iterable<String> queries,
    String evalName,
    Iterable<String>? expectedOutput,
    Iterable<Iterable<ExpectedToolCall>>? expectedToolCalls,
    CancellationToken cancellationToken, {
    AgentEvaluator? evaluator,
    ConversationSplitter? splitter,
    int? numRepetitions,
    ChatConfiguration? chatConfiguration,
    Iterable<AgentEvaluator>? evaluators,
    Iterable<AgentResponse>? responses,
  }) async {
    var items = await runAgentForEvalAsync(
      agent,
      queries,
      expectedOutput,
      expectedToolCalls,
      splitter,
      numRepetitions,
      cancellationToken,
    );
    return await evaluator
        .evaluateAsync(items, evalName, cancellationToken)
        ;
  }
}

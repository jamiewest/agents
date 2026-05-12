import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_response_extensions.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'agent_evaluation_results.dart';
import 'agent_evaluator.dart';
import 'conversation_splitter.dart';
import 'eval_item.dart';
import 'expected_tool_call.dart';
import 'meai_evaluator_adapter.dart';

/// Extension methods for evaluating agents and responses.
extension AgentEvaluationExtensions on AIAgent {
  /// Evaluates an agent by running it against test queries and scoring the
  /// responses.
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
    final queryList = queries.toList();
    final repetitions = numRepetitions ?? 1;
    if (repetitions < 1) {
      throw ArgumentError.value(
        numRepetitions,
        'numRepetitions',
        'Number of repetitions must be greater than zero.',
      );
    }

    final expectedOutputList = expectedOutput?.toList();
    if (expectedOutputList != null &&
        expectedOutputList.length != queryList.length) {
      throw ArgumentError.value(
        expectedOutput,
        'expectedOutput',
        'Expected output count must match query count.',
      );
    }

    final expectedToolCallList = expectedToolCalls
        ?.map((e) => e.toList())
        .toList();
    if (expectedToolCallList != null &&
        expectedToolCallList.length != queryList.length) {
      throw ArgumentError.value(
        expectedToolCalls,
        'expectedToolCalls',
        'Expected tool-call count must match query count.',
      );
    }

    final evaluatorList = <AgentEvaluator>[
      ?evaluator,
      ...?evaluators,
    ];
    if (evaluatorList.isEmpty && chatConfiguration != null) {
      throw ArgumentError(
        'A concrete Evaluator must be supplied via evaluator/evaluators; chatConfiguration is used only by MeaiEvaluatorAdapter.',
      );
    }
    if (evaluatorList.isEmpty) {
      throw ArgumentError.notNull('evaluator');
    }

    final providedResponses = responses?.toList();
    final totalRuns = queryList.length * repetitions;
    if (providedResponses != null && providedResponses.length != totalRuns) {
      throw ArgumentError.value(
        responses,
        'responses',
        'Response count must match query count multiplied by repetitions.',
      );
    }

    final items = <EvalItem>[];
    var responseIndex = 0;
    for (var repetition = 0; repetition < repetitions; repetition++) {
      for (var queryIndex = 0; queryIndex < queryList.length; queryIndex++) {
        final query = queryList[queryIndex];
        final response = providedResponses != null
            ? providedResponses[responseIndex++]
            : await run(
                null,
                AgentRunOptions(),
                cancellationToken: cancellationToken,
                message: query,
              );
        final responseMessages = response.messages.isNotEmpty
            ? response.messages
            : [ChatMessage.fromText(ChatRole.assistant, response.text)];
        final conversation = [
          ChatMessage.fromText(ChatRole.user, query),
          ...responseMessages,
        ];
        final item =
            EvalItem(
                query: query,
                response: response.text,
                conversation: conversation,
                splitter: splitter,
              )
              ..expectedOutput = expectedOutputList?[queryIndex]
              ..expectedToolCalls = expectedToolCallList?[queryIndex]
              ..rawResponse = response.asChatResponse();
        items.add(item);
      }
    }

    if (evaluatorList.length == 1) {
      return evaluatorList.single.evaluate(
        items,
        evalName: evalName,
        cancellationToken: cancellationToken,
      );
    }

    final subResults = <String, AgentEvaluationResults>{};
    final mergedResults = List<EvaluationResult>.generate(
      items.length,
      (_) => EvaluationResult(),
    );
    for (final agentEvaluator in evaluatorList) {
      final result = await agentEvaluator.evaluate(
        items,
        evalName: evalName,
        cancellationToken: cancellationToken,
      );
      subResults[agentEvaluator.name] = result;
      for (
        var i = 0;
        i < result.items.length && i < mergedResults.length;
        i++
      ) {
        mergedResults[i].metrics.addAll(result.items[i].metrics);
      }
    }

    return AgentEvaluationResults(
      'CompositeEvaluator',
      mergedResults,
      inputItems: items,
    )..subResults = subResults;
  }

  /// Wraps an MEAI [Evaluator] and evaluates this agent with it.
  Future<AgentEvaluationResults> evaluateWithMeai(
    Iterable<String> queries,
    String evalName,
    Evaluator evaluator,
    ChatConfiguration chatConfiguration, {
    Iterable<String>? expectedOutput,
    Iterable<Iterable<ExpectedToolCall>>? expectedToolCalls,
    ConversationSplitter? splitter,
    int? numRepetitions,
    CancellationToken? cancellationToken,
  }) {
    return evaluate(
      queries,
      evalName,
      expectedOutput,
      expectedToolCalls,
      cancellationToken ?? CancellationToken.none,
      evaluator: MeaiEvaluatorAdapter(evaluator, chatConfiguration),
      splitter: splitter,
      numRepetitions: numRepetitions,
    );
  }
}

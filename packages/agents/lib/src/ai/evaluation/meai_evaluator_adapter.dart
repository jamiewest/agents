import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'agent_evaluation_results.dart';
import 'agent_evaluator.dart';
import 'eval_item.dart';

/// Adapter that wraps an MEAI [Evaluator] into an [AgentEvaluator].
class MeaiEvaluatorAdapter implements AgentEvaluator {
  MeaiEvaluatorAdapter(this._evaluator, this._chatConfiguration);

  final Evaluator _evaluator;
  final ChatConfiguration _chatConfiguration;

  @override
  String get name => _evaluator.runtimeType.toString();

  @override
  Future<AgentEvaluationResults> evaluate(
    List<EvalItem> items, {
    String? evalName,
    CancellationToken? cancellationToken,
  }) async {
    final results = <EvaluationResult>[];
    for (final item in items) {
      cancellationToken?.throwIfCancellationRequested();
      final (queryMessages, _) = item.split();
      final modelResponse =
          item.rawResponse ??
          ChatResponse.fromMessage(
            ChatMessage.fromText(ChatRole.assistant, item.response),
          );
      final result = await _evaluator.evaluate(
        queryMessages,
        modelResponse,
        chatConfiguration: _chatConfiguration,
        cancellationToken: cancellationToken,
      );
      results.add(result);
    }
    return AgentEvaluationResults(name, results, inputItems: items);
  }
}

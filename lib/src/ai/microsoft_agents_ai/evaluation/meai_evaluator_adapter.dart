import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import 'agent_evaluation_results.dart';
import 'agent_evaluator.dart';
import 'eval_item.dart';

/// Adapter that wraps an MEAI [Evaluator] into an [AgentEvaluator]. Runs the
/// MEAI evaluator per-item and aggregates results.
class MeaiEvaluatorAdapter implements AgentEvaluator {
  /// Initializes a new instance of the [MeaiEvaluatorAdapter] class.
  ///
  /// [evaluator] The MEAI evaluator to wrap.
  ///
  /// [chatConfiguration] Chat configuration for the evaluator (includes the
  /// judge model).
  MeaiEvaluatorAdapter(Evaluator evaluator, ChatConfiguration chatConfiguration)
    : _evaluator = evaluator,
      _chatConfiguration = chatConfiguration {
  }

  final Evaluator _evaluator;

  final ChatConfiguration _chatConfiguration;

  String get name {
    return this._evaluator.runtimeType.toString();
  }

  @override
  Future<AgentEvaluationResults> evaluate(
    List<EvalItem> items, {
    String? evalName,
    CancellationToken? cancellationToken,
  }) async {
    var results = List<EvaluationResult>(items.length);
    for (final item in items) {
      cancellationToken.throwIfCancellationRequested();
      var (queryMessages, _) = item.split();
      var messages = queryMessages.toList();
      var chatResponse =
          item.rawResponse ??
          chatResponse(ChatMessage.fromText(ChatRole.assistant, item.response));
      var result = await this._evaluator
          .evaluateAsync(
            messages,
            chatResponse,
            this._chatConfiguration,
            cancellationToken: cancellationToken,
          )
          ;
      results.add(result);
    }
    return agentEvaluationResults(this.name, results, inputItems: items);
  }
}

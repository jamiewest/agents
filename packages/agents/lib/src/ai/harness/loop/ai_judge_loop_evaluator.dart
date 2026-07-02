import 'dart:convert';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'ai_judge_loop_evaluator_options.dart';
import 'judge_verdict.dart';
import 'loop_context.dart';
import 'loop_evaluation.dart';
import 'loop_evaluator.dart';

/// The JSON schema describing the structured [JudgeVerdict] requested from the
/// judge chat client.
const Map<String, dynamic> _judgeVerdictSchema = {
  'type': 'object',
  'properties': {
    'answered': {
      'type': 'boolean',
      'description':
          'True if the agent has fully addressed the original request, '
          'otherwise false.',
    },
    'gapAnalysis': {
      'type': 'string',
      'description':
          "When 'answered' is false, explain what is still missing or what "
          'work remains to fully address the original request.',
    },
  },
  'required': ['answered', 'gapAnalysis'],
  'additionalProperties': false,
};

/// A [LoopEvaluator] that uses a separate judge [ChatClient] to decide whether
/// the user's original request has been fully addressed, continuing the loop
/// (with the judge's gap analysis as feedback) while the answer is "no".
///
/// After each iteration the judge is queried directly (without any agent tools,
/// session, or middleware) with the original request and the agent's latest
/// response, and asked for a structured [JudgeVerdict]. If the judge client does
/// not honor structured output, the verdict falls back to parsing the raw text
/// for the non-overlapping [doneVerdictMarker] / [moreVerdictMarker] markers
/// (with [moreVerdictMarker] winning when the verdict is ambiguous or absent, so
/// the loop keeps running).
///
/// LLM-judged loops are costly and probabilistic, so consider setting a stricter
/// max-iterations cap on the owning loop agent.
class AIJudgeLoopEvaluator extends LoopEvaluator {
  /// The verdict marker the judge emits (for clients that do not honor
  /// structured output) when the original request has been fully addressed.
  static const String doneVerdictMarker = 'VERDICT: DONE';

  /// The verdict marker the judge emits when more work is still required. Takes
  /// precedence over [doneVerdictMarker] when both (or neither) are present.
  static const String moreVerdictMarker = 'VERDICT: MORE';

  /// The placeholder token within the instructions that is replaced with the
  /// rendered criteria. When no criteria are supplied, the placeholder is
  /// removed.
  static const String criteriaPlaceholder = '{criteria}';

  /// The placeholder token within the feedback template that is replaced with
  /// the judge's gap analysis.
  static const String gapAnalysisPlaceholder = '{gap_analysis}';

  /// The default system instructions used to prompt the judge.
  static const String defaultInstructions =
      "You are an evaluator. You are given a user's original request and an "
      "agent's latest response. "
      'Decide whether the agent has fully addressed the original request. '
      "Set 'answered' to true if the request has been fully addressed, or "
      'false if more work is still required. '
      "When 'answered' is false, use 'gapAnalysis' to explain what is still "
      'missing or what work remains. '
      'If you cannot return structured output, reply with '
      '$doneVerdictMarker when the request has been fully addressed, or '
      '$moreVerdictMarker when more work is still required.'
      '$criteriaPlaceholder';

  /// The default template used to build the feedback produced when the request
  /// is not yet answered.
  static const String defaultFeedbackMessageTemplate =
      'Your previous response did not fully address the original request. '
      'The following is still missing or incomplete: $gapAnalysisPlaceholder '
      'Please continue and fully address the original request.';

  static const String _unknownGapAnalysis = '<unknown>';

  /// Creates an [AIJudgeLoopEvaluator] backed by [judgeClient].
  AIJudgeLoopEvaluator(
    ChatClient judgeClient, {
    AIJudgeLoopEvaluatorOptions? options,
  }) : _judgeClient = judgeClient,
       _instructions = (options?.instructions ?? defaultInstructions)
           .replaceAll(criteriaPlaceholder, _renderCriteria(options?.criteria)),
       _feedbackMessageTemplate =
           options?.feedbackMessageTemplate ?? defaultFeedbackMessageTemplate;

  final ChatClient _judgeClient;
  final String _instructions;
  final String _feedbackMessageTemplate;

  @override
  Future<LoopEvaluation> evaluate(
    LoopContext context, {
    CancellationToken? cancellationToken,
  }) async {
    // Build the judge's user message from AIContent so non-text request content
    // (images, data, etc.) is preserved rather than flattened to text.
    final userContents = <AIContent>[
      TextContent(
        '# Has the original request been fully addressed?\n\n'
        '## Original request:\n',
      ),
    ];
    for (final message in context.initialMessages) {
      userContents.addAll(message.contents);
    }
    userContents.add(
      TextContent(
        "\n\n## Agent's latest response:\n${context.lastResponse.text}",
      ),
    );

    final judgeMessages = <ChatMessage>[
      ChatMessage(
        role: ChatRole.system,
        contents: [TextContent(_instructions)],
      ),
      ChatMessage(role: ChatRole.user, contents: userContents),
    ];

    final response = await _judgeClient.getResponse(
      messages: judgeMessages,
      options: ChatOptions(
        responseFormat: ChatResponseFormat.forJsonSchema(
          schema: _judgeVerdictSchema,
          schemaName: 'JudgeVerdict',
        ),
      ),
      cancellationToken: cancellationToken,
    );

    bool answered;
    var gapAnalysis = _unknownGapAnalysis;
    final verdict = _tryParseVerdict(response.text);
    if (verdict != null) {
      answered = verdict.answered;
      if (verdict.gapAnalysis.trim().isNotEmpty) {
        gapAnalysis = verdict.gapAnalysis;
      }
    } else {
      // Fallback for clients that do not honor structured output: look for the
      // explicit, non-overlapping verdict markers. moreVerdictMarker wins so an
      // ambiguous or marker-less reply keeps looping rather than stopping on an
      // incomplete answer.
      final text = response.text.toUpperCase();
      answered =
          !text.contains(moreVerdictMarker) && text.contains(doneVerdictMarker);
    }

    if (answered) {
      return LoopEvaluation.stop();
    }

    final feedback = _feedbackMessageTemplate.replaceAll(
      gapAnalysisPlaceholder,
      gapAnalysis,
    );
    return LoopEvaluation.proceed(feedback);
  }

  static JudgeVerdict? _tryParseVerdict(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic> && decoded.containsKey('answered')) {
        return JudgeVerdict.fromJson(decoded);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static String _renderCriteria(Iterable<String>? criteria) {
    if (criteria == null) {
      return '';
    }
    final builder = StringBuffer();
    for (final criterion in criteria) {
      if (criterion.trim().isNotEmpty) {
        builder
          ..write('\n- ')
          ..write(criterion);
      }
    }
    if (builder.isEmpty) {
      return '';
    }
    return '\n\nThe response must satisfy all of the following criteria:'
        '$builder';
  }
}

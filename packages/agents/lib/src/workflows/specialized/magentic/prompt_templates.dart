import '../../magentic_default_prompts.dart';
import 'magentic_task_context.dart';

/// Matches a single-brace placeholder token, for example `{task}` or
/// `{old_facts}`. Only `{word}` sequences are treated as placeholders, so
/// literal braces in a prompt (such as JSON in an override) are left untouched.
final RegExp _placeholderPattern = RegExp(r'\{(\w+)\}');

/// Substitutes the named placeholders in [template] with [values].
///
/// This is a single pass over the template: substituted values are never
/// re-scanned for further placeholders, so content that happens to contain
/// `{token}` text (the task, for example) is not corrupted. A placeholder that
/// is not one of [values] is left as its original text.
String _substitute(String template, Map<String, String> values) =>
    template.replaceAllMapped(
      _placeholderPattern,
      (match) => values[match.group(1)] ?? match.group(0)!,
    );

String _generalLanguageDirective(String language) =>
    'Write your entire response in $language, including any section headings '
    'or labels. Do not use any other language.';

String _progressLedgerLanguageDirective(String language) =>
    'When filling in the JSON, write every "reason" value and the '
    '"instruction_or_question" answer in $language. Do not translate the JSON '
    'keys - they must remain exactly as shown above. The "next_speaker" '
    'answer must remain exactly one of the provided team member names and '
    'must not be translated.';

/// Builds the manager prompts used throughout a Magentic task.
///
/// Each prompt body comes from [MagenticPromptOverrides] when the task
/// configures one and from [MagenticDefaultPrompts] otherwise. When a response
/// language is configured, a directive pinning that language is appended
/// *after* the (possibly overridden) body: a concrete language name is
/// followed far more reliably than a relative "match the request" instruction,
/// especially for the progress ledger's JSON free-text fields.
extension MagenticPromptTemplates on MagenticTaskContext {
  String _appendLanguageDirective(String body) {
    final language = responseLanguage;
    return language == null || language.isEmpty
        ? body
        : '$body\n\n${_generalLanguageDirective(language)}';
  }

  String _appendProgressLedgerLanguageDirective(String body) {
    final language = responseLanguage;
    return language == null || language.isEmpty
        ? body
        : '$body\n\n${_progressLedgerLanguageDirective(language)}';
  }

  /// Prompt requesting the initial fact-sheet pre-survey.
  String toTaskLedgerFactsPrompt() => _appendLanguageDirective(
    _substitute(
      promptOverrides?.taskLedgerFactsPrompt ??
          MagenticDefaultPrompts.taskLedgerFactsPrompt,
      {'task': task},
    ),
  );

  /// Prompt requesting an updated fact sheet after a stall.
  String toTaskLedgerFactsUpdatePrompt() => _appendLanguageDirective(
    _substitute(
      promptOverrides?.taskLedgerFactsUpdatePrompt ??
          MagenticDefaultPrompts.taskLedgerFactsUpdatePrompt,
      {'task': task, 'old_facts': taskLedger?.currentFacts.text ?? ''},
    ),
  );

  /// Prompt requesting the initial bullet-point plan.
  String toTaskLedgerPlanPrompt() => _appendLanguageDirective(
    _substitute(
      promptOverrides?.taskLedgerPlanPrompt ??
          MagenticDefaultPrompts.taskLedgerPlanPrompt,
      {'team': teamDescription},
    ),
  );

  /// Prompt requesting an updated plan after a stall.
  String toTaskLedgerPlanUpdatePrompt() => _appendLanguageDirective(
    _substitute(
      promptOverrides?.taskLedgerPlanUpdatePrompt ??
          MagenticDefaultPrompts.taskLedgerPlanUpdatePrompt,
      {'team': teamDescription},
    ),
  );

  /// Prompt presenting the full task ledger (facts + plan) to the team.
  ///
  /// No language directive is appended: nothing is generated from this prompt,
  /// and its facts and plan are already localized by the prompts that produced
  /// them.
  String toTaskLedgerFullPrompt() => _substitute(
    promptOverrides?.taskLedgerFullPrompt ??
        MagenticDefaultPrompts.taskLedgerFullPrompt,
    {
      'task': task,
      'team': teamDescription,
      'facts': taskLedger?.currentFacts.text ?? '',
      'plan': taskLedger?.currentPlan.text ?? '',
    },
  );

  /// Prompt requesting the per-round progress ledger answers.
  String toProgressLedgerPrompt() {
    final (questions, schema) = progressLedger.formatQuestions();
    return _appendProgressLedgerLanguageDirective(
      _substitute(
        promptOverrides?.progressLedgerPrompt ??
            MagenticDefaultPrompts.progressLedgerPrompt,
        {
          'task': task,
          'team': teamDescription,
          'questions': questions,
          'schema': schema,
        },
      ),
    );
  }

  /// Prompt requesting the final answer once the task is complete.
  String toFinalAnswerPrompt() => _appendLanguageDirective(
    _substitute(
      promptOverrides?.finalAnswerPrompt ??
          MagenticDefaultPrompts.finalAnswerPrompt,
      {'task': task},
    ),
  );
}

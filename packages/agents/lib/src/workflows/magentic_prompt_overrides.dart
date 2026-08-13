import 'magentic_default_prompts.dart';

/// Replacement prompt bodies for the Magentic manager.
///
/// Every field is optional; a `null` field falls back to the corresponding
/// [MagenticDefaultPrompts] template. Overrides keep the same named
/// single-brace placeholders (for example `{task}`), which the framework
/// substitutes at render time — a placeholder an override omits is simply
/// never filled in, and one that is not available to that prompt is left as
/// literal text.
class MagenticPromptOverrides {
  /// Creates a set of prompt overrides.
  const MagenticPromptOverrides({
    this.taskLedgerFactsPrompt,
    this.taskLedgerPlanPrompt,
    this.taskLedgerFullPrompt,
    this.taskLedgerFactsUpdatePrompt,
    this.taskLedgerPlanUpdatePrompt,
    this.progressLedgerPrompt,
    this.finalAnswerPrompt,
  });

  /// Replaces [MagenticDefaultPrompts.taskLedgerFactsPrompt].
  final String? taskLedgerFactsPrompt;

  /// Replaces [MagenticDefaultPrompts.taskLedgerPlanPrompt].
  final String? taskLedgerPlanPrompt;

  /// Replaces [MagenticDefaultPrompts.taskLedgerFullPrompt].
  final String? taskLedgerFullPrompt;

  /// Replaces [MagenticDefaultPrompts.taskLedgerFactsUpdatePrompt].
  final String? taskLedgerFactsUpdatePrompt;

  /// Replaces [MagenticDefaultPrompts.taskLedgerPlanUpdatePrompt].
  final String? taskLedgerPlanUpdatePrompt;

  /// Replaces [MagenticDefaultPrompts.progressLedgerPrompt].
  final String? progressLedgerPrompt;

  /// Replaces [MagenticDefaultPrompts.finalAnswerPrompt].
  final String? finalAnswerPrompt;
}

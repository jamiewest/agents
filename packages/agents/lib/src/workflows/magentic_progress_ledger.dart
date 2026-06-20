/// Maintains a ledger of progress made by a Magentic workflow.
///
/// Each coordination round the manager answers a fixed set of questions plus
/// any caller-supplied additional questions. The answers drive completion,
/// stall, and next-speaker decisions.
class MagenticProgressLedger {
  /// Creates a progress ledger for a team described by [teamNames].
  ///
  /// [additionalQuestions] are appended after the standard slots. An optional
  /// [state] map seeds the ledger from a previously captured answer set.
  MagenticProgressLedger(
    String teamNames, {
    Iterable<ProgressLedgerSlot> additionalQuestions = const [],
    Map<String, Object?>? state,
  }) : this._(
         StringProgressLedgerSlot(
           'next_speaker',
           'Who should speak next? (select from: $teamNames)',
         ),
         List<ProgressLedgerSlot>.unmodifiable(additionalQuestions),
         state,
       );

  MagenticProgressLedger._(
    this.nextSpeakerSlot,
    this.additionalQuestions, [
    Map<String, Object?>? state,
  ]) {
    if (state != null) {
      tryUpdateState(state);
    }
  }

  /// Returns an independent copy capturing the current answers.
  ///
  /// Events carry a snapshot rather than the live ledger so that, in the
  /// centralized model where several coordination rounds run within one
  /// super-step, each emitted event preserves the values from its own round.
  MagenticProgressLedger snapshot() {
    final captured = _state;
    return MagenticProgressLedger._(
      nextSpeakerSlot,
      additionalQuestions,
      captured == null ? null : Map<String, Object?>.of(captured),
    );
  }

  /// Whether the request is fully satisfied.
  static final BooleanProgressLedgerSlot isRequestSatisfiedSlot =
      BooleanProgressLedgerSlot(
        'is_request_satisfied',
        'Is the request fully satisfied? (True if complete, or False if the '
            'original request has yet to be SUCCESSFULLY and FULLY addressed)',
      );

  /// Whether the team is repeating itself.
  static final BooleanProgressLedgerSlot isInLoopSlot =
      BooleanProgressLedgerSlot(
        'is_in_loop',
        'Are we in a loop where we are repeating the same requests and or '
            'getting the same responses as before? Loops can span multiple '
            'turns, and can include repeated actions like scrolling up or down '
            'more than a handful of times.',
      );

  /// Whether forward progress is being made.
  static final BooleanProgressLedgerSlot isProgressBeingMadeSlot =
      BooleanProgressLedgerSlot(
        'is_progress_being_made',
        'Are we making forward progress? (True if just starting, or recent '
            'messages are adding value. False if recent messages show evidence '
            'of being stuck in a loop or if there is evidence of significant '
            'barriers to success such as the inability to read from a required '
            'file)',
      );

  /// Which team member should speak next.
  final StringProgressLedgerSlot nextSpeakerSlot;

  /// The instruction or question to relay to the next speaker.
  static final StringProgressLedgerSlot instructionOrQuestionSlot =
      StringProgressLedgerSlot(
        'instruction_or_question',
        'What instruction or question would you give this team member? (Phrase '
            'as if speaking directly to them, and include any specific '
            'information they may need)',
      );

  /// Caller-supplied additional questions appended after the standard slots.
  final List<ProgressLedgerSlot> additionalQuestions;

  Map<String, Object?>? _state;

  bool _isRequestSatisfied = false;
  bool _isInLoop = false;
  bool _isProgressBeingMade = false;
  String _nextSpeaker = '';
  String _instructionOrQuestion = '';

  /// The raw captured answer set, or `null` if no answers have been recorded.
  Map<String, Object?>? get state => _state;

  /// Whether plan execution has started (any answers have been recorded).
  bool get isStarted => _state != null;

  /// Whether the task has been fully satisfied.
  bool get isRequestSatisfied => _isRequestSatisfied;

  /// Whether the team is in a loop.
  bool get isInLoop => _isInLoop;

  /// Whether the team is making progress on the task.
  bool get isProgressBeingMade => _isProgressBeingMade;

  /// The next team member to take a turn.
  String get nextSpeaker => _nextSpeaker;

  /// The instruction or question to send to the next team member.
  String get instructionOrQuestion => _instructionOrQuestion;

  /// The full ordered set of slots, including additional questions.
  List<ProgressLedgerSlot> get slots => [
    isRequestSatisfiedSlot,
    isInLoopSlot,
    isProgressBeingMadeSlot,
    nextSpeakerSlot,
    instructionOrQuestionSlot,
    ...additionalQuestions,
  ];

  /// Attempts to update the ledger from an [element] answer set.
  ///
  /// Returns `true` only when every required question has a usable answer, in
  /// which case the ledger state and derived values are updated.
  bool tryUpdateState(Map<String, Object?> element) {
    final isRequestSatisfied = isRequestSatisfiedSlot.tryGetValue(element);
    final isInLoop = isInLoopSlot.tryGetValue(element);
    final isProgressBeingMade = isProgressBeingMadeSlot.tryGetValue(element);
    final nextSpeaker = nextSpeakerSlot.tryGetValue(element);
    final instructionOrQuestion = instructionOrQuestionSlot.tryGetValue(
      element,
    );

    final answered =
        isRequestSatisfied != null &&
        isInLoop != null &&
        isProgressBeingMade != null &&
        nextSpeaker != null &&
        instructionOrQuestion != null;

    if (answered) {
      _state = element;
      _isRequestSatisfied = isRequestSatisfied;
      _isInLoop = isInLoop;
      _isProgressBeingMade = isProgressBeingMade;
      _nextSpeaker = nextSpeaker;
      _instructionOrQuestion = instructionOrQuestion;
    }

    return answered;
  }

  (String questionBlock, String answerSchema)? _questionFormatCache;

  /// Formats the slot questions and the answer JSON schema for the prompt.
  (String questionBlock, String answerSchema) formatQuestions() {
    final cache = _questionFormatCache;
    if (cache != null) {
      return cache;
    }

    final questionBuilder = StringBuffer();
    final schemaBuilder = StringBuffer()..writeln('{');
    for (final slot in slots) {
      questionBuilder.writeln(slot.formattedQuestion);
      schemaBuilder
        ..writeln('"${slot.key}": {')
        ..writeln(
          '   "${ProgressLedgerSlot.valueKey}": '
          '${slot.schemaType}${slot.suffixString},',
        )
        ..writeln('   "${ProgressLedgerSlot.reasonKey}": string')
        ..writeln('}');
    }
    schemaBuilder.writeln('}');

    final result = (questionBuilder.toString(), schemaBuilder.toString());
    _questionFormatCache = result;
    return result;
  }
}

/// A single question slot in a [MagenticProgressLedger].
abstract class ProgressLedgerSlot {
  /// Creates a progress ledger slot.
  const ProgressLedgerSlot(this.key, this.question, {this.schemaTypeSuffix});

  /// JSON property name holding a slot's answer value.
  static const String valueKey = 'answer';

  /// JSON property name holding a slot's reasoning.
  static const String reasonKey = 'reason';

  /// The slot key used in prompts and answer JSON.
  final String key;

  /// The natural-language question presented to the manager.
  final String question;

  /// Optional schema type suffix appended in the answer schema.
  final String? schemaTypeSuffix;

  /// The JSON schema type of the slot's answer (e.g. `boolean`, `string`).
  String get schemaType;

  /// The parenthesised schema-type suffix, or empty when none.
  String get suffixString =>
      schemaTypeSuffix == null ? '' : '($schemaTypeSuffix)';

  /// The question formatted as an indented bullet for the prompt.
  String get formattedQuestion {
    final lines = question
        .split(RegExp(r'[\r\n]'))
        .where((line) => line.isNotEmpty)
        .map((line) => line.trimRight());
    return '    - ${lines.join('\n      ')}';
  }

  /// Reads the raw answer value at this slot, or `null` when absent.
  Object? readRawValue(Map<String, Object?> answers) {
    final slot = answers[key];
    if (slot is Map) {
      final value = slot[valueKey];
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  /// Reads the raw reason at this slot, or `null` when absent.
  String? readReason(Map<String, Object?> answers) {
    final slot = answers[key];
    if (slot is Map) {
      final reason = slot[reasonKey];
      if (reason is String) {
        return reason;
      }
    }
    return null;
  }
}

/// A boolean-valued [ProgressLedgerSlot].
class BooleanProgressLedgerSlot extends ProgressLedgerSlot {
  /// Creates a boolean slot.
  const BooleanProgressLedgerSlot(
    super.key,
    super.question, {
    super.schemaTypeSuffix,
  });

  @override
  String get schemaType => 'boolean';

  /// Reads the boolean answer at this slot, or `null` when absent or invalid.
  bool? tryGetValue(Map<String, Object?> answers) {
    final value = readRawValue(answers);
    return value is bool ? value : null;
  }
}

/// A string-valued [ProgressLedgerSlot].
class StringProgressLedgerSlot extends ProgressLedgerSlot {
  /// Creates a string slot.
  const StringProgressLedgerSlot(
    super.key,
    super.question, {
    super.schemaTypeSuffix,
  });

  @override
  String get schemaType => 'string';

  /// Reads the string answer at this slot, or `null` when absent or invalid.
  String? tryGetValue(Map<String, Object?> answers) {
    final value = readRawValue(answers);
    return value is String ? value : null;
  }
}

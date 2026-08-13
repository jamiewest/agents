/// The built-in English prompt templates a Magentic manager uses.
///
/// They are public so callers can read them and base a
/// `MagenticPromptOverrides` on one instead of writing a prompt from scratch.
///
/// Each template contains named single-brace placeholders (for example
/// `{task}`) that are substituted when the prompt is rendered. A placeholder
/// that is not one of the tokens available to a given prompt is left as-is, so
/// literal braces — JSON in an override, for instance — pass through untouched.
class MagenticDefaultPrompts {
  const MagenticDefaultPrompts._();

  /// Requests the initial fact-sheet pre-survey. Placeholder: `{task}`.
  static const String taskLedgerFactsPrompt = '''
Below I will present you a request.

Before we begin addressing the request, please answer the following pre-survey to the best of your ability.
        Keep in mind that you are Ken Jennings-level with trivia, and Mensa-level with puzzles, so there should be
        a deep well to draw from.

        Here is the request:

{task}

    Here is the pre-survey:

    1. Please list any specific facts or figures that are GIVEN in the request itself.It is possible that
       there are none.
    2. Please list any facts that may need to be looked up, and WHERE SPECIFICALLY they might be found.
       In some cases, authoritative sources are mentioned in the request itself.
    3. Please list any facts that may need to be derived(e.g., via logical deduction, simulation, or computation)
    4. Please list any facts that are recalled from memory, hunches, well-reasoned guesses, etc.

When answering this survey, keep in mind that "facts" will typically be specific names, dates, statistics, etc.
Your answer should use headings:

    1. GIVEN OR VERIFIED FACTS
    2. FACTS TO LOOK UP
    3. FACTS TO DERIVE
    4. EDUCATED GUESSES

DO NOT include any other headings or sections in your response.DO NOT list next steps or plans until asked to do so.''';

  /// Requests an updated fact sheet after a stall. Placeholders: `{task}`,
  /// `{old_facts}`.
  static const String taskLedgerFactsUpdatePrompt = '''
As a reminder, we are working to solve the following task:

{task}

It is clear we are not making as much progress as we would like, but we may have learned something new.
Please rewrite the following fact sheet, updating it to include anything new we have learned that may be helpful.

Example edits can include (but are not limited to) adding new guesses, moving educated guesses to verified facts
if appropriate, etc. Updates may be made to any section of the fact sheet, and more than one section of the fact
sheet can be edited. This is an especially good time to update educated guesses, so please at least add or update
one educated guess or hunch, and explain your reasoning.

Here is the old fact sheet:

{old_facts}''';

  /// Requests the initial bullet-point plan. Placeholder: `{team}`.
  static const String taskLedgerPlanPrompt = '''
Fantastic. To address this request we have assembled the following team:

{team}

Based on the team composition, and known and unknown facts, please devise a short bullet-point plan for addressing the
original request. Remember, there is no requirement to involve all team members. A team member's particular expertise
may not be needed for this task.''';

  /// Requests an updated plan after a stall. Placeholder: `{team}`.
  static const String taskLedgerPlanUpdatePrompt = '''
Please briefly explain what went wrong on this last run
(the root cause of the failure), and then come up with a new plan that takes steps and includes hints to overcome prior
challenges and especially avoids repeating the same mistakes. As before, the new plan should be concise, expressed in
bullet-point form, and consider the following team composition:

{team}''';

  /// Presents the full task ledger (facts + plan) to the team. Placeholders:
  /// `{task}`, `{team}`, `{facts}`, `{plan}`.
  static const String taskLedgerFullPrompt = '''
We are working to address the following user request:

{task}


To answer this request we have assembled the following team:

{team}


Here is an initial fact sheet to consider:

{facts}


Here is the plan to follow as best as possible:

{plan}''';

  /// Requests the per-round progress ledger answers. Placeholders: `{task}`,
  /// `{team}`, `{questions}`, `{schema}`.
  static const String progressLedgerPrompt = '''
Recall we are working on the following request:

{task}

And we have assembled the following team:

{team}

To make progress on the request, please answer the following questions, including necessary reasoning:

{questions}

Please output an answer in pure JSON format according to the following schema. The JSON object must be parsable as-is.
DO NOT OUTPUT ANYTHING OTHER THAN JSON, AND DO NOT DEVIATE FROM THIS SCHEMA:

{schema}''';

  /// Requests the final answer once the task is complete. Placeholder:
  /// `{task}`.
  static const String finalAnswerPrompt = '''
We are working on the following task:
{task}

We have completed the task.

The above messages contain the conversation that took place to complete the task.

Based on the information gathered, provide the final answer to the original request.
The answer should be phrased as if you were speaking to the user. ''';
}

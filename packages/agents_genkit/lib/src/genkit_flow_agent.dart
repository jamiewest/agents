import 'package:agents/agents.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

/// An [AIAgent] that delegates invocations to a Genkit flow or async function.
///
/// Wrap any `Future<String> Function(String)` — including a Genkit [Flow]
/// called via `(input) => flow(input)` — and it participates in the full
/// agent session/skill/context-provider ecosystem.
///
/// Example:
/// ```dart
/// final flow = genkit.defineFlow(
///   name: 'chat',
///   fn: (input, _) async => await model.generate(prompt: input),
/// );
/// final agent = GenkitFlowAgent(
///   name: 'chat-agent',
///   run: (input) => flow(input),
/// );
/// ```
class GenkitFlowAgent extends AIAgent {
  /// Creates a [GenkitFlowAgent].
  ///
  /// [run] is called with the text of the last user message. It must return
  /// the assistant's reply as a plain string.
  GenkitFlowAgent({
    String? name,
    String? description,
    required Future<String> Function(String input) run,
  })  : _name = name,
        _description = description,
        _run = run;

  final String? _name;
  final String? _description;
  final Future<String> Function(String input) _run;

  @override
  String? get name => _name;

  @override
  String? get description => _description;

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async =>
      ChatClientAgentSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async {
    if (session is ChatClientAgentSession) return session.serialize();
    return null;
  }

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async {
    if (serializedState is String) {
      return ChatClientAgentSession.deserialize(serializedState);
    }
    return ChatClientAgentSession();
  }

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final input = _extractInput(messages);
    final output = await _run(input);
    return AgentResponse(
      message: ChatMessage(
        role: ChatRole.assistant,
        contents: [TextContent(output)],
      ),
    );
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final response = await runCore(
      messages,
      session: session,
      options: options,
      cancellationToken: cancellationToken,
    );
    for (final update in response.toAgentResponseUpdates()) {
      yield update;
    }
  }

  String _extractInput(Iterable<ChatMessage> messages) {
    final last = messages.lastWhere(
      (m) => m.role == ChatRole.user,
      orElse: () => messages.last,
    );
    return last.text;
  }
}

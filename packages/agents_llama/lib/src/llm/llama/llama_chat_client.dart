/// A Microsoft.Extensions.AI [ChatClient] backed by on-device llama.cpp.
library;

import 'dart:async';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../diagnostics/prompt_inspector.dart';
import '../../models/model_spec.dart';
import '../../runtime/llama_runtime_api.dart';
import '../chat_format.dart';

/// Resolves the loaded [LlamaSession] this client generates against.
///
/// The session is owned and loaded elsewhere (the model-loading hosted
/// service); the returned future completes once the model is ready.
typedef SessionProvider = Future<LlamaSession> Function();

/// Returns [messages] with [instructions] materialized as the leading system
/// message.
///
/// M.E.AI carries system instructions out-of-band in
/// [ChatOptions.instructions]; converting them into an in-band system message
/// is the chat client's job (the `extensions` OpenAI client does the same).
/// [ChatFormat]s only render a system turn from an actual system-role
/// message, so without this step the harness instructions and every
/// `AIContextProvider`'s contributed instructions are silently dropped from
/// the prompt.
///
/// If the conversation already starts with a system message the two are
/// merged into one (instructions first): Gemma's wire format has a single
/// system turn, and a second system-role message mid-prompt would render as
/// its own bogus turn.
List<ChatMessage> messagesWithInstructions(
  Iterable<ChatMessage> messages,
  String? instructions,
) {
  final trimmed = instructions?.trim();
  final list = messages.toList();
  if (trimmed == null || trimmed.isEmpty) return list;

  ChatMessage system(String text) => ChatMessage(
    role: ChatRole.system,
    contents: <AIContent>[TextContent(text)],
  );

  if (list.isNotEmpty && list.first.role == ChatRole.system) {
    return <ChatMessage>[
      system('$trimmed\n\n${list.first.text}'),
      ...list.skip(1),
    ];
  }
  return <ChatMessage>[system(trimmed), ...list];
}

/// Bridges the M.E.AI chat abstractions to a model running through
/// `LlamaFlutter`.
///
/// This is the **inner** client: wrap it with `FunctionInvokingChatClient` so
/// tool calls it surfaces (as [FunctionCallContent]) are executed and fed back.
/// All model-family specifics — prompt rendering and the prose/reasoning/
/// tool-call stream split — live in the injected [ChatFormat]. The model is
/// loaded by a hosted service and supplied through [sessionProvider]; this
/// client does not own its lifecycle.
class LlamaChatClient extends ChatClient {
  LlamaChatClient({
    required this.sessionProvider,
    required this.format,
    required this.contextSize,
    this.sampling = const SamplingDefaults(),
    this.inspector,
    this.isThinkingEnabled,
  });

  /// Resolves the ready session; the caller owns its lifecycle.
  final SessionProvider sessionProvider;

  /// The model family's prompt rendering and output decoding.
  final ChatFormat format;

  /// The model's context window in tokens, recorded on each [PromptSnapshot]
  /// so the UI can gauge how full the context is.
  final int contextSize;

  /// Generation defaults used when the per-request [ChatOptions] doesn't
  /// override them.
  final SamplingDefaults sampling;

  /// Optional sink that records each rendered prompt and its resolved sampling
  /// config so the UI can show exactly what was sent to the model.
  final PromptInspector? inspector;

  /// Reads whether to request the family's reasoning channel, evaluated per
  /// request so a runtime toggle takes effect on the next turn. Null means
  /// thinking is always off. The result is still gated on
  /// [ChatFormat.supportsThinking].
  final bool Function()? isThinkingEnabled;

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final session = await sessionProvider();
    final tools = (options?.tools ?? const <AITool>[])
        .whereType<AIFunctionDeclaration>();
    final thinking =
        (isThinkingEnabled?.call() ?? false) && format.supportsThinking;
    final prompt = format.render(
      messagesWithInstructions(messages, options?.instructions),
      tools: tools,
      enableThinking: thinking,
    );

    final maxTokens = options?.maxOutputTokens ?? sampling.maxTokens;
    final temperature = options?.temperature ?? sampling.temperature;
    final topK = options?.topK ?? sampling.topK;
    final topP = options?.topP ?? sampling.topP;
    final seed = options?.seed ?? sampling.seed;

    inspector?.record(
      PromptSnapshot(
        text: prompt.text,
        stopSequences: prompt.stopSequences,
        maxTokens: maxTokens,
        temperature: temperature,
        topK: topK,
        topP: topP,
        seed: seed,
        imageCount: prompt.images.length,
        contextSize: contextSize,
        capturedAt: DateTime.now(),
      ),
    );

    var tokens = session.generate(
      prompt.text,
      maxTokens: maxTokens,
      temperature: temperature,
      topK: topK,
      topP: topP,
      seed: seed,
      stopSequences: prompt.stopSequences,
      images: prompt.images.isEmpty ? null : prompt.images,
    );
    if (cancellationToken != null) {
      tokens = tokens.takeWhile(
        (_) => !cancellationToken.isCancellationRequested,
      );
    }

    yield* format.decode(tokens);
  }

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final text = StringBuffer();
    final extras = <AIContent>[];
    await for (final update in getStreamingResponse(
      messages: messages,
      options: options,
      cancellationToken: cancellationToken,
    )) {
      for (final content in update.contents) {
        if (content is TextContent) {
          text.write(content.text);
        } else {
          extras.add(content);
        }
      }
    }
    return ChatResponse(
      messages: <ChatMessage>[
        ChatMessage(
          role: ChatRole.assistant,
          contents: <AIContent>[
            if (text.isNotEmpty) TextContent(text.toString()),
            ...extras,
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    // The session is owned by the hosted service that loaded it, not here.
  }
}

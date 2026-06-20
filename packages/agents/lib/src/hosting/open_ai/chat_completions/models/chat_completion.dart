// Copyright (c) Microsoft. All rights reserved.
//
// Ported from ChatCompletions/Models/ChatCompletion.cs.

import 'chat_completion_choice.dart';
import 'completion_usage.dart';

/// A chat-completion response returned by the model.
class ChatCompletion {
  /// Creates a [ChatCompletion].
  const ChatCompletion({
    required this.id,
    required this.created,
    required this.model,
    required this.choices,
    this.usage,
    this.serviceTier,
    this.systemFingerprint,
  });

  /// A unique identifier for the chat completion.
  final String id;

  /// The Unix timestamp (seconds) of when the completion was created.
  final int created;

  /// The model used for the chat completion.
  final String model;

  /// The list of completion choices.
  final List<ChatCompletionChoice> choices;

  /// Usage statistics for the completion request.
  final CompletionUsage? usage;

  /// The service tier used for processing.
  final String? serviceTier;

  /// The backend configuration fingerprint.
  final String? systemFingerprint;

  /// The object type, always `chat.completion`.
  String get object => 'chat.completion';

  /// Serializes this completion, omitting null fields.
  Map<String, dynamic> toJson() => {
    'id': id,
    'object': object,
    'created': created,
    'model': model,
    'choices': choices.map((c) => c.toJson()).toList(),
    if (usage != null) 'usage': usage!.toJson(),
    if (serviceTier != null) 'service_tier': serviceTier,
    if (systemFingerprint != null) 'system_fingerprint': systemFingerprint,
  };
}

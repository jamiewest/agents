// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/Models/CreateResponse.cs.
//
// The full upstream request carries ~30 fields; this port types the ones the
// executor/service consume and keeps the remainder accessible via [raw].

import 'conversation_reference.dart';
import 'response_input.dart';

/// A request to create a model response for the given [input].
class CreateResponse {
  /// Creates a [CreateResponse].
  const CreateResponse({
    required this.input,
    this.model,
    this.instructions,
    this.stream,
    this.store,
    this.previousResponseId,
    this.temperature,
    this.topP,
    this.maxOutputTokens,
    this.metadata,
    this.conversation,
    this.raw = const {},
  });

  /// Parses a [CreateResponse] from a decoded JSON object.
  factory CreateResponse.fromJson(Map<String, dynamic> json) => CreateResponse(
    input: ResponseInput.fromJson(json['input']),
    model: json['model'] as String?,
    instructions: json['instructions'] as String?,
    stream: json['stream'] as bool?,
    store: json['store'] as bool?,
    previousResponseId: json['previous_response_id'] as String?,
    temperature: (json['temperature'] as num?)?.toDouble(),
    topP: (json['top_p'] as num?)?.toDouble(),
    maxOutputTokens: json['max_output_tokens'] as int?,
    metadata: (json['metadata'] as Map?)?.cast<String, String>(),
    conversation: json['conversation'] == null
        ? null
        : ConversationReference.fromJson(json['conversation']),
    raw: json,
  );

  /// The input to the response.
  final ResponseInput input;

  /// The model ID.
  final String? model;

  /// System-level instructions.
  final String? instructions;

  /// Whether to stream the response.
  final bool? stream;

  /// Whether to persist the response.
  final bool? store;

  /// The ID of a previous response to continue from.
  final String? previousResponseId;

  /// Sampling temperature.
  final double? temperature;

  /// Nucleus sampling probability mass.
  final double? topP;

  /// Upper bound on generated tokens.
  final int? maxOutputTokens;

  /// Developer-defined metadata.
  final Map<String, String>? metadata;

  /// The conversation this response belongs to.
  final ConversationReference? conversation;

  /// The full decoded request JSON (for fields not modeled explicitly).
  final Map<String, dynamic> raw;
}

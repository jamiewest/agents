// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/Models/CreateResponse.cs.
//
// The full upstream request carries ~30 fields; this port types the ones the
// executor/service consume and keeps the remainder accessible via [raw].

import 'agent_reference.dart';
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
    this.tools,
    this.toolChoice,
    this.agent,
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
    tools: (json['tools'] as List?)?.cast<Object?>(),
    toolChoice: json['tool_choice'],
    agent: json['agent'] == null
        ? null
        : AgentReference.fromJson(json['agent'] as Map<String, dynamic>),
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

  /// The raw `tools` array supplied on the request.
  final List<Object?>? tools;

  /// The raw `tool_choice` value supplied on the request.
  final Object? toolChoice;

  /// The agent reference supplied on the request.
  final AgentReference? agent;

  /// The full decoded request JSON (for fields not modeled explicitly).
  final Map<String, dynamic> raw;
}

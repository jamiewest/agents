// Copyright (c) Microsoft. All rights reserved.
//
// Ported from ChatCompletions/Models/CreateChatCompletion.cs.

import 'chat_completion_request_message.dart';
import 'response_format.dart';
import 'stop_sequences.dart';
import 'tool.dart';
import 'tool_choice.dart';

/// Represents an OpenAI chat-completion request.
class CreateChatCompletion {
  /// Creates a [CreateChatCompletion].
  CreateChatCompletion({
    required this.messages,
    required this.model,
    this.frequencyPenalty,
    this.maxCompletionTokens,
    this.maxTokens,
    this.metadata,
    this.modalities,
    this.n,
    this.parallelToolCalls,
    this.presencePenalty,
    this.reasoningEffort,
    this.responseFormat,
    this.safetyIdentifier,
    this.seed,
    this.serviceTier,
    this.stop,
    this.store,
    this.stream,
    this.temperature,
    this.toolChoice,
    this.tools,
    this.topP,
    this.verbosity,
  });

  /// Parses a [CreateChatCompletion] from a decoded JSON map.
  factory CreateChatCompletion.fromJson(Map<String, dynamic> json) {
    return CreateChatCompletion(
      messages: (json['messages'] as List)
          .map(
            (m) => ChatCompletionRequestMessage.fromJson(
              m as Map<String, dynamic>,
            ),
          )
          .toList(),
      model: json['model'] as String,
      frequencyPenalty: _toDouble(json['frequency_penalty']),
      maxCompletionTokens: json['max_completion_tokens'] as int?,
      maxTokens: json['max_tokens'] as int?,
      metadata: (json['metadata'] as Map?)?.cast<String, String>(),
      modalities: (json['modalities'] as List?)?.cast<String>(),
      n: json['n'] as int?,
      parallelToolCalls: json['parallel_tool_calls'] as bool?,
      presencePenalty: _toDouble(json['presence_penalty']),
      reasoningEffort: json['reasoning_effort'] as String?,
      responseFormat: json['response_format'] == null
          ? null
          : ResponseFormat.fromJson(
              json['response_format'] as Map<String, dynamic>,
            ),
      safetyIdentifier: json['safety_identifier'] as String?,
      seed: json['seed'] as int?,
      serviceTier: json['service_tier'] as String?,
      stop: json['stop'] == null ? null : StopSequences.fromJson(json['stop']),
      store: json['store'] as bool?,
      stream: json['stream'] as bool?,
      temperature: _toDouble(json['temperature']),
      toolChoice: json['tool_choice'] == null
          ? null
          : ToolChoice.fromJson(json['tool_choice']),
      tools: (json['tools'] as List?)
          ?.map((t) => Tool.fromJson(t as Map<String, dynamic>))
          .toList(),
      topP: _toDouble(json['top_p']),
      verbosity: json['verbosity'] as String?,
    );
  }

  /// The messages comprising the conversation so far.
  final List<ChatCompletionRequestMessage> messages;

  /// The model ID used to generate the response.
  final String model;

  /// Penalizes new tokens based on their existing frequency.
  final double? frequencyPenalty;

  /// Upper bound for the number of generated completion tokens.
  final int? maxCompletionTokens;

  /// Deprecated maximum number of tokens to generate.
  final int? maxTokens;

  /// Developer-defined metadata.
  final Map<String, String>? metadata;

  /// Output modalities (`text` and/or `audio`).
  final List<String>? modalities;

  /// Number of completions to generate.
  final int? n;

  /// Whether to enable parallel tool calling.
  final bool? parallelToolCalls;

  /// Penalizes new tokens based on whether they appear so far.
  final double? presencePenalty;

  /// The reasoning effort level for o-series models.
  final String? reasoningEffort;

  /// The format the model must output.
  final ResponseFormat? responseFormat;

  /// A stable identifier used to help detect policy-violating users.
  final String? safetyIdentifier;

  /// Seed for deterministic sampling.
  final int? seed;

  /// The service tier used for processing.
  final String? serviceTier;

  /// Up to four sequences that stop generation.
  final StopSequences? stop;

  /// Whether to store the output for distillation/evals.
  final bool? store;

  /// Whether to stream partial progress.
  final bool? stream;

  /// Sampling temperature.
  final double? temperature;

  /// Controls which tool (if any) the model calls.
  final ToolChoice? toolChoice;

  /// The tools the model may call.
  final List<Tool>? tools;

  /// Nucleus sampling probability mass.
  final double? topP;

  /// Verbosity of the model response.
  final String? verbosity;

  static double? _toDouble(Object? value) =>
      value == null ? null : (value as num).toDouble();
}

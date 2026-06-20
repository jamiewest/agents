// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/Models/Response.cs.

import 'item_resource.dart';

/// The status of a response.
enum ResponseStatus {
  /// The response completed successfully.
  completed('completed'),

  /// The response failed.
  failed('failed'),

  /// The response is still being generated.
  inProgress('in_progress'),

  /// The response was cancelled.
  cancelled('cancelled'),

  /// The response is queued for processing.
  queued('queued'),

  /// The response is incomplete.
  incomplete('incomplete');

  const ResponseStatus(this.wireValue);

  /// The snake_case wire representation.
  final String wireValue;
}

/// A model response returned by the Responses API.
class Response {
  /// Creates a [Response].
  Response({
    required this.id,
    required this.createdAt,
    required this.status,
    this.model,
    List<ItemResource>? output,
    this.usage,
    this.error,
    this.instructions,
    this.metadata,
    this.previousResponseId,
    this.conversationId,
  }) : output = output ?? [];

  /// The unique identifier for the response.
  final String id;

  /// The Unix timestamp (seconds) of when the response was created.
  final int createdAt;

  /// The status of the response.
  ResponseStatus status;

  /// The model used.
  final String? model;

  /// The output items produced by the model.
  List<ItemResource> output;

  /// Token usage statistics.
  ResponseUsage? usage;

  /// Error details, when the response failed.
  ResponseError? error;

  /// The instructions used.
  final String? instructions;

  /// Developer-defined metadata.
  final Map<String, String>? metadata;

  /// The ID of the previous response, when continuing.
  final String? previousResponseId;

  /// The conversation ID, when attached to a conversation.
  final String? conversationId;

  /// The object type, always `response`.
  String get object => 'response';

  /// Whether this response is in a terminal (non-running) state.
  bool get isTerminal =>
      status == ResponseStatus.completed ||
      status == ResponseStatus.failed ||
      status == ResponseStatus.cancelled ||
      status == ResponseStatus.incomplete;

  /// Serializes this response, omitting null fields.
  Map<String, dynamic> toJson() => {
    'id': id,
    'object': object,
    'created_at': createdAt,
    'status': status.wireValue,
    if (model != null) 'model': model,
    'output': output.map((i) => i.toJson()).toList(),
    if (usage != null) 'usage': usage!.toJson(),
    if (error != null) 'error': error!.toJson(),
    if (instructions != null) 'instructions': instructions,
    if (metadata != null) 'metadata': metadata,
    if (previousResponseId != null) 'previous_response_id': previousResponseId,
    if (conversationId != null) 'conversation': {'id': conversationId},
  };
}

/// Error details for a failed response.
class ResponseError {
  /// Creates a [ResponseError].
  const ResponseError({required this.message, this.code});

  /// The error code.
  final String? code;

  /// The error message.
  final String message;

  /// Serializes this error.
  Map<String, dynamic> toJson() => {
    if (code != null) 'code': code,
    'message': message,
  };
}

/// Token usage statistics for a response.
class ResponseUsage {
  /// Creates a [ResponseUsage].
  const ResponseUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.totalTokens = 0,
    this.cachedTokens = 0,
    this.reasoningTokens = 0,
  });

  /// A zero-valued usage record.
  static const ResponseUsage zero = ResponseUsage();

  /// Input (prompt) tokens.
  final int inputTokens;

  /// Output (completion) tokens.
  final int outputTokens;

  /// Total tokens.
  final int totalTokens;

  /// Cached input tokens.
  final int cachedTokens;

  /// Reasoning tokens.
  final int reasoningTokens;

  /// Serializes this usage record.
  Map<String, dynamic> toJson() => {
    'input_tokens': inputTokens,
    'input_tokens_details': {'cached_tokens': cachedTokens},
    'output_tokens': outputTokens,
    'output_tokens_details': {'reasoning_tokens': reasoningTokens},
    'total_tokens': totalTokens,
  };
}

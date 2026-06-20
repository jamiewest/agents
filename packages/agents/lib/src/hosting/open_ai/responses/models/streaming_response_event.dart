// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/Models/StreamingResponseEvent.cs.
//
// Upstream defines 19 event variants. This port implements the text and
// function-call path (the common cases); other variants (audio/image/reasoning
// summary/workflow/MCP/function-approval) can be added following this pattern.

import 'item_resource.dart';
import 'response.dart';

/// Base class for Responses API streaming events.
abstract class StreamingResponseEvent {
  /// Creates a [StreamingResponseEvent].
  StreamingResponseEvent({this.sequenceNumber = 0});

  /// The event type discriminator (for example `response.output_text.delta`).
  String get type;

  /// The monotonic sequence number, assigned as events are emitted.
  int sequenceNumber;

  /// Serializes this event, including `type` and `sequence_number`.
  Map<String, dynamic> toJson() => {
    'type': type,
    'sequence_number': sequenceNumber,
    ...payload(),
  };

  /// The variant-specific fields (excludes `type`/`sequence_number`).
  Map<String, dynamic> payload();
}

/// `response.created`.
class StreamingResponseCreated extends StreamingResponseEvent {
  /// Creates a [StreamingResponseCreated].
  StreamingResponseCreated(this.response, {super.sequenceNumber});

  /// The created (in-progress) response.
  final Response response;

  @override
  String get type => 'response.created';

  @override
  Map<String, dynamic> payload() => {'response': response.toJson()};
}

/// `response.in_progress`.
class StreamingResponseInProgress extends StreamingResponseEvent {
  /// Creates a [StreamingResponseInProgress].
  StreamingResponseInProgress(this.response, {super.sequenceNumber});

  /// The in-progress response.
  final Response response;

  @override
  String get type => 'response.in_progress';

  @override
  Map<String, dynamic> payload() => {'response': response.toJson()};
}

/// `response.completed`.
class StreamingResponseCompleted extends StreamingResponseEvent {
  /// Creates a [StreamingResponseCompleted].
  StreamingResponseCompleted(this.response, {super.sequenceNumber});

  /// The completed response.
  final Response response;

  @override
  String get type => 'response.completed';

  @override
  Map<String, dynamic> payload() => {'response': response.toJson()};
}

/// `response.failed`.
class StreamingResponseFailed extends StreamingResponseEvent {
  /// Creates a [StreamingResponseFailed].
  StreamingResponseFailed(this.response, {super.sequenceNumber});

  /// The failed response.
  final Response response;

  @override
  String get type => 'response.failed';

  @override
  Map<String, dynamic> payload() => {'response': response.toJson()};
}

/// `response.output_item.added`.
class StreamingOutputItemAdded extends StreamingResponseEvent {
  /// Creates a [StreamingOutputItemAdded].
  StreamingOutputItemAdded({
    required this.outputIndex,
    required this.item,
    super.sequenceNumber,
  });

  /// The index of the output item.
  final int outputIndex;

  /// The added item.
  final ItemResource item;

  @override
  String get type => 'response.output_item.added';

  @override
  Map<String, dynamic> payload() => {
    'output_index': outputIndex,
    'item': item.toJson(),
  };
}

/// `response.output_item.done`.
class StreamingOutputItemDone extends StreamingResponseEvent {
  /// Creates a [StreamingOutputItemDone].
  StreamingOutputItemDone({
    required this.outputIndex,
    required this.item,
    super.sequenceNumber,
  });

  /// The index of the output item.
  final int outputIndex;

  /// The completed item.
  final ItemResource item;

  @override
  String get type => 'response.output_item.done';

  @override
  Map<String, dynamic> payload() => {
    'output_index': outputIndex,
    'item': item.toJson(),
  };
}

/// `response.output_text.delta`.
class StreamingOutputTextDelta extends StreamingResponseEvent {
  /// Creates a [StreamingOutputTextDelta].
  StreamingOutputTextDelta({
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.delta,
    super.sequenceNumber,
  });

  /// The ID of the item being streamed.
  final String itemId;

  /// The index of the output item.
  final int outputIndex;

  /// The index of the content part.
  final int contentIndex;

  /// The text delta.
  final String delta;

  @override
  String get type => 'response.output_text.delta';

  @override
  Map<String, dynamic> payload() => {
    'item_id': itemId,
    'output_index': outputIndex,
    'content_index': contentIndex,
    'delta': delta,
    'logprobs': const [],
  };
}

/// `response.output_text.done`.
class StreamingOutputTextDone extends StreamingResponseEvent {
  /// Creates a [StreamingOutputTextDone].
  StreamingOutputTextDone({
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.text,
    super.sequenceNumber,
  });

  /// The ID of the item.
  final String itemId;

  /// The index of the output item.
  final int outputIndex;

  /// The index of the content part.
  final int contentIndex;

  /// The full text of the content part.
  final String text;

  @override
  String get type => 'response.output_text.done';

  @override
  Map<String, dynamic> payload() => {
    'item_id': itemId,
    'output_index': outputIndex,
    'content_index': contentIndex,
    'text': text,
  };
}

/// `response.function_call_arguments.delta`.
class StreamingFunctionCallArgumentsDelta extends StreamingResponseEvent {
  /// Creates a [StreamingFunctionCallArgumentsDelta].
  StreamingFunctionCallArgumentsDelta({
    required this.itemId,
    required this.outputIndex,
    required this.delta,
    super.sequenceNumber,
  });

  /// The ID of the function-call item.
  final String itemId;

  /// The index of the output item.
  final int outputIndex;

  /// The arguments delta.
  final String delta;

  @override
  String get type => 'response.function_call_arguments.delta';

  @override
  Map<String, dynamic> payload() => {
    'item_id': itemId,
    'output_index': outputIndex,
    'delta': delta,
  };
}

/// `response.function_call_arguments.done`.
class StreamingFunctionCallArgumentsDone extends StreamingResponseEvent {
  /// Creates a [StreamingFunctionCallArgumentsDone].
  StreamingFunctionCallArgumentsDone({
    required this.itemId,
    required this.outputIndex,
    required this.arguments,
    super.sequenceNumber,
  });

  /// The ID of the function-call item.
  final String itemId;

  /// The index of the output item.
  final int outputIndex;

  /// The complete arguments JSON string.
  final String arguments;

  @override
  String get type => 'response.function_call_arguments.done';

  @override
  Map<String, dynamic> payload() => {
    'item_id': itemId,
    'output_index': outputIndex,
    'arguments': arguments,
  };
}

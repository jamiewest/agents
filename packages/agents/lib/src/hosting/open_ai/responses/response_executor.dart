// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/IResponseExecutor.cs.

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'agent_invocation_context.dart';
import 'models/create_response.dart';
import 'models/response.dart';
import 'models/streaming_response_event.dart';

/// Executes response generation, emitting a stream of streaming events.
abstract interface class ResponseExecutor {
  /// Validates a request, returning a [ResponseError] when invalid, else null.
  Future<ResponseError?> validateRequest(
    CreateResponse request, {
    CancellationToken? cancellationToken,
  });

  /// Executes [request] and emits streaming response events.
  ///
  /// [conversationHistory] is prepended to the agent's input when provided.
  Stream<StreamingResponseEvent> execute(
    AgentInvocationContext context,
    CreateResponse request, {
    List<ChatMessage>? conversationHistory,
    CancellationToken? cancellationToken,
  });
}

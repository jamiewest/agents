// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/IResponsesService.cs.

import 'package:extensions/system.dart';

import '../models/list_response.dart';
import '../models/sort_order.dart';
import 'models/create_response.dart';
import 'models/item_resource.dart';
import 'models/response.dart';
import 'models/streaming_response_event.dart';

/// Service interface for OpenAI Responses API operations.
abstract interface class ResponsesService {
  /// The default page size for list operations.
  static const int defaultListLimit = 20;

  /// Validates a request, returning a [ResponseError] when invalid, else null.
  Future<ResponseError?> validateRequest(
    CreateResponse request, {
    CancellationToken? cancellationToken,
  });

  /// Creates a response (non-streaming).
  Future<Response> createResponse(
    CreateResponse request, {
    CancellationToken? cancellationToken,
  });

  /// Creates a response, streaming its events.
  Stream<StreamingResponseEvent> createResponseStreaming(
    CreateResponse request, {
    CancellationToken? cancellationToken,
  });

  /// Retrieves a response by ID, or null when not found.
  Future<Response?> getResponse(
    String responseId, {
    CancellationToken? cancellationToken,
  });

  /// Replays the streaming events of a response, after [startingAfter].
  Stream<StreamingResponseEvent> getResponseStreaming(
    String responseId, {
    int? startingAfter,
    CancellationToken? cancellationToken,
  });

  /// Cancels an in-progress response.
  Future<Response> cancelResponse(
    String responseId, {
    CancellationToken? cancellationToken,
  });

  /// Deletes a response; true when it existed.
  Future<bool> deleteResponse(
    String responseId, {
    CancellationToken? cancellationToken,
  });

  /// Lists the input items for a response with cursor pagination.
  Future<ListResponse<ItemResource>> listResponseInputItems(
    String responseId, {
    int? limit,
    SortOrder? order,
    String? after,
    String? before,
    CancellationToken? cancellationToken,
  });
}

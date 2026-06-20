// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/ResponsesHttpHandler.cs.
//
// Returns framework-agnostic [ApiResult]s for non-streaming operations; the
// router handles the SSE streaming branches directly against the service.

import 'package:extensions/system.dart';

import '../api_result.dart';
import '../models/delete_response.dart';
import '../models/error_response.dart';
import '../models/sort_order.dart';
import 'models/create_response.dart';
import 'models/response.dart';
import 'responses_service.dart';

/// Handles non-streaming OpenAI Responses API operations.
class ResponsesHandler {
  /// Creates a [ResponsesHandler].
  ResponsesHandler(this.service);

  /// The backing service (also used by the router for streaming).
  final ResponsesService service;

  /// Creates a model response (non-streaming).
  Future<ApiResult> createResponse(
    CreateResponse request, {
    CancellationToken? cancellationToken,
  }) async {
    final error = await service.validateRequest(
      request,
      cancellationToken: cancellationToken,
    );
    if (error != null) {
      return ApiResult.badRequest(_error(error.message, code: error.code));
    }

    try {
      final response = await service.createResponse(
        request,
        cancellationToken: cancellationToken,
      );
      switch (response.status) {
        case ResponseStatus.failed:
          return ApiResult(
            500,
            _error(
              response.error?.message ?? 'Internal Server Error',
              type: 'server_error',
              code: response.error?.code,
            ),
          );
        case ResponseStatus.queued:
          return ApiResult(202, response.toJson());
        default:
          return ApiResult.ok(response.toJson());
      }
    } catch (e) {
      return ApiResult(500, _error(e.toString(), type: 'server_error'));
    }
  }

  /// Retrieves a response by ID.
  Future<ApiResult> getResponse(
    String responseId, {
    CancellationToken? cancellationToken,
  }) async {
    final response = await service.getResponse(
      responseId,
      cancellationToken: cancellationToken,
    );
    return response != null
        ? ApiResult.ok(response.toJson())
        : ApiResult.notFound(_error("Response '$responseId' not found."));
  }

  /// Cancels an in-progress response.
  Future<ApiResult> cancelResponse(
    String responseId, {
    CancellationToken? cancellationToken,
  }) async {
    try {
      final response = await service.cancelResponse(
        responseId,
        cancellationToken: cancellationToken,
      );
      return ApiResult.ok(response.toJson());
    } on StateError catch (e) {
      return ApiResult.badRequest(_error(e.message));
    }
  }

  /// Deletes a response.
  Future<ApiResult> deleteResponse(
    String responseId, {
    CancellationToken? cancellationToken,
  }) async {
    final deleted = await service.deleteResponse(
      responseId,
      cancellationToken: cancellationToken,
    );
    return deleted
        ? ApiResult.ok(
            DeleteResponse(
              id: responseId,
              object: 'response',
              deleted: true,
            ).toJson(),
          )
        : ApiResult.notFound(_error("Response '$responseId' not found."));
  }

  /// Lists the input items for a response.
  Future<ApiResult> listResponseInputItems(
    String responseId, {
    int? limit,
    String? order,
    String? after,
    String? before,
    CancellationToken? cancellationToken,
  }) async {
    try {
      final result = await service.listResponseInputItems(
        responseId,
        limit: limit,
        order: _parseOrder(order),
        after: after,
        before: before,
        cancellationToken: cancellationToken,
      );
      return ApiResult.ok(result.toJson((i) => i.toJson()));
    } on StateError catch (e) {
      return ApiResult.notFound(_error(e.message));
    }
  }

  static SortOrder? _parseOrder(String? order) {
    switch (order?.toLowerCase()) {
      case null:
        return null;
      case 'asc':
        return SortOrder.ascending;
      case 'desc':
        return SortOrder.descending;
      default:
        throw StateError(
          "Invalid order value: $order. Must be 'asc' or 'desc'.",
        );
    }
  }

  static Map<String, dynamic> _error(
    String message, {
    String type = 'invalid_request_error',
    String? code,
  }) => ErrorResponse(
    error: ErrorDetails(message: message, type: type, code: code),
  ).toJson();
}

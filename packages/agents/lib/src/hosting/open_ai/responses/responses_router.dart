// Copyright (c) Microsoft. All rights reserved.
//
// Ported from EndpointRouteBuilderExtensions.Responses.cs.
//
// Builds a `shelf_router` [Router] for the OpenAI Responses API. Mount it at
// `/v1/responses` (or `/<agentName>/v1/responses`) in the host.

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../api_result.dart';
import '../sse_json_result.dart';
import 'models/create_response.dart';
import 'models/streaming_response_event.dart';
import 'responses_handler.dart';
import 'responses_service.dart';

/// Builds a [Router] exposing the OpenAI Responses API backed by [service].
///
/// Routes are relative, so mount the returned router at `/v1/responses`.
Router openAIResponsesRouter({required ResponsesService service}) {
  final handler = ResponsesHandler(service);
  final router = Router();

  router.post('/', (Request request) async {
    final body = await _readJson(request);
    final createRequest = CreateResponse.fromJson(body);
    final shouldStream =
        _boolQuery(request, 'stream') ?? createRequest.stream ?? false;

    if (shouldStream) {
      final error = await service.validateRequest(createRequest);
      if (error != null) {
        return _toResponse(
          ApiResult.badRequest({
            'error': {
              'message': error.message,
              'type': 'invalid_request_error',
              if (error.code != null) 'code': error.code,
            },
          }),
        );
      }
      return sseJsonResult<StreamingResponseEvent>(
        service.createResponseStreaming(createRequest),
        toJson: (event) => event.toJson(),
        getEventType: (event) => event.type,
      );
    }

    return _toResponse(await handler.createResponse(createRequest));
  });

  router.get('/<responseId>', (Request request, String responseId) async {
    if (_boolQuery(request, 'stream') == true) {
      final startingAfterRaw = request.url.queryParameters['starting_after'];
      return sseJsonResult<StreamingResponseEvent>(
        service.getResponseStreaming(
          responseId,
          startingAfter: startingAfterRaw == null
              ? null
              : int.tryParse(startingAfterRaw),
        ),
        toJson: (event) => event.toJson(),
        getEventType: (event) => event.type,
      );
    }
    return _toResponse(await handler.getResponse(responseId));
  });

  router.post('/<responseId>/cancel', (
    Request request,
    String responseId,
  ) async {
    return _toResponse(await handler.cancelResponse(responseId));
  });

  router.delete('/<responseId>', (Request request, String responseId) async {
    return _toResponse(await handler.deleteResponse(responseId));
  });

  router.get('/<responseId>/input_items', (
    Request request,
    String responseId,
  ) async {
    final query = request.url.queryParameters;
    final limitRaw = query['limit'];
    return _toResponse(
      await handler.listResponseInputItems(
        responseId,
        limit: limitRaw == null ? null : int.tryParse(limitRaw),
        order: query['order'],
        after: query['after'],
        before: query['before'],
      ),
    );
  });

  return router;
}

Future<Map<String, dynamic>> _readJson(Request request) async {
  final body = await request.readAsString();
  if (body.isEmpty) {
    return <String, dynamic>{};
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

bool? _boolQuery(Request request, String name) {
  final value = request.url.queryParameters[name];
  if (value == null) {
    return null;
  }
  return value == 'true' || value == '1';
}

Response _toResponse(ApiResult result) => Response(
  result.statusCode,
  body: result.body == null ? null : jsonEncode(result.body),
  headers: {'content-type': 'application/json'},
);

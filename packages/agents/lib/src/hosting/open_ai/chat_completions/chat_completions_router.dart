// Copyright (c) Microsoft. All rights reserved.
//
// Ported from EndpointRouteBuilderExtensions.ChatCompletions.cs.
//
// The C# original maps ASP.NET endpoints. This port builds an equivalent
// `shelf_router` [Router] that mounts `POST /<agentName>/v1/chat/completions`
// and delegates to [AIAgentChatCompletionsProcessor]. Agent resolution is left
// to the host via the [resolveAgent] callback (matching the a2a precedent).

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../abstractions/ai_agent.dart';
import '../sse_json_result.dart';
import 'ai_agent_chat_completions_processor.dart';
import 'models/chat_completion_chunk.dart';
import 'models/create_chat_completion.dart';

/// Resolves an [AIAgent] by the `agentName` route segment.
typedef ResolveAgent = AIAgent Function(String agentName);

/// Builds a [Router] exposing OpenAI chat-completions for resolved agents.
///
/// Mounts `POST /<agentName>/v1/chat/completions`. Streaming requests
/// (`"stream": true`) produce a Server-Sent Events response; non-streaming
/// requests produce a single JSON [Response].
Router openAIChatCompletionsRouter({required ResolveAgent resolveAgent}) {
  final router = Router();

  router.post('/<agentName>/v1/chat/completions', (
    Request request,
    String agentName,
  ) async {
    final AIAgent agent;
    try {
      agent = resolveAgent(agentName);
    } catch (_) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'message': "Agent '$agentName' was not found.",
            'type': 'invalid_request_error',
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final body = await request.readAsString();
    final createRequest = CreateChatCompletion.fromJson(
      jsonDecode(body) as Map<String, dynamic>,
    );

    if (createRequest.stream == true) {
      final chunks = AIAgentChatCompletionsProcessor.streamChatCompletion(
        agent,
        createRequest,
      );
      return sseJsonResult<ChatCompletionChunk>(
        chunks,
        toJson: (chunk) => chunk.toJson(),
      );
    }

    final completion =
        await AIAgentChatCompletionsProcessor.createChatCompletion(
          agent,
          createRequest,
        );
    return Response.ok(
      jsonEncode(completion.toJson()),
      headers: {'content-type': 'application/json'},
    );
  });

  return router;
}

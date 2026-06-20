// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Microsoft.Agents.AI.Hosting.OpenAI/SseJsonResult.cs.
//
// The C# original is an `IResult` that writes Server-Sent Events to the
// ASP.NET response body. This port produces a framework-agnostic `shelf`
// [Response] whose body streams the same SSE wire format.

import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Builds a `shelf` [Response] that streams [events] as Server-Sent Events.
///
/// Each item is JSON-encoded via [toJson]. When [getEventType] returns a
/// non-null value for an item, an `event:` line is emitted before its `data:`
/// line, matching the OpenAI streaming wire format.
Response sseJsonResult<T>(
  Stream<T> events, {
  required Object? Function(T item) toJson,
  String? Function(T item)? getEventType,
}) {
  final body = events.map((item) {
    final buffer = StringBuffer();
    final eventType = getEventType?.call(item);
    if (eventType != null && eventType.isNotEmpty) {
      buffer.write('event: $eventType\n');
    }
    buffer.write('data: ${jsonEncode(toJson(item))}\n\n');
    return utf8.encode(buffer.toString());
  });

  return Response.ok(
    body,
    headers: <String, String>{
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache,no-store',
      'connection': 'keep-alive',
      'content-encoding': 'identity',
    },
    context: <String, Object>{'shelf.io.buffer_output': false},
  );
}

// Copyright (c) Microsoft. All rights reserved.
//
// Framework-agnostic stand-in for ASP.NET's `IResult`. Handlers return an
// [ApiResult]; the shelf routers translate it into an HTTP response.

/// A status code paired with an already-JSON-encodable body.
class ApiResult {
  /// Creates an [ApiResult] with [statusCode] and [body].
  const ApiResult(this.statusCode, this.body);

  /// A `200 OK` result carrying [body].
  factory ApiResult.ok(Object? body) => ApiResult(200, body);

  /// A `400 Bad Request` result carrying [body].
  factory ApiResult.badRequest(Object? body) => ApiResult(400, body);

  /// A `404 Not Found` result carrying [body].
  factory ApiResult.notFound(Object? body) => ApiResult(404, body);

  /// The HTTP status code.
  final int statusCode;

  /// The response body, as a JSON-encodable value (or null for no body).
  final Object? body;
}

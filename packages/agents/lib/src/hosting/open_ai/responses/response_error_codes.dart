// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/ResponseErrorCodes.cs.

/// Well-known error codes returned by response request validation, together
/// with their mapping to the HTTP status code a handler should return for
/// each. Centralizing the codes avoids scattering string literals and keeps
/// the status mapping in a single place.
abstract final class ResponseErrorCodes {
  /// The request was malformed or violated a request-level constraint
  /// (HTTP 400).
  static const invalidRequest = 'invalid_request';

  /// A conversation referenced by the request does not exist (HTTP 404).
  static const conversationNotFound = 'conversation_not_found';

  /// Maps a validation error code to the HTTP status code and the wire error
  /// code a handler should return for it. Not-found codes map to HTTP 404
  /// with a `null` wire code (matching the OpenAI error body, whose semantics
  /// are carried by the error `type`); every other validation failure maps
  /// to HTTP 400 and keeps its code.
  static (int, String?) mapValidationError(String? code) => switch (code) {
    conversationNotFound => (404, null),
    _ => (400, code),
  };
}

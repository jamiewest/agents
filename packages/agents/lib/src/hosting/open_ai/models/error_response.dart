// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Microsoft.Agents.AI.Hosting.OpenAI/Models/ErrorResponse.cs.

/// Represents an error response from the OpenAI APIs.
class ErrorResponse {
  /// Creates an [ErrorResponse].
  const ErrorResponse({required this.error});

  /// The error details.
  final ErrorDetails error;

  /// Serializes this error response.
  Map<String, dynamic> toJson() => <String, dynamic>{'error': error.toJson()};
}

/// Represents the details of an error.
class ErrorDetails {
  /// Creates [ErrorDetails].
  const ErrorDetails({
    required this.message,
    required this.type,
    this.code,
    this.param,
  });

  /// The error message.
  final String message;

  /// The error type.
  final String type;

  /// The error code.
  final String? code;

  /// The parameter that caused the error.
  final String? param;

  /// Serializes these error details, omitting null fields.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'message': message,
    'type': type,
    if (code != null) 'code': code,
    if (param != null) 'param': param,
  };
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:extensions/ai.dart';

/// Continuation token for polling a background A2A task response.
class A2AContinuationToken extends ResponseContinuationToken {
  /// Creates an [A2AContinuationToken] for the given [taskId].
  A2AContinuationToken(this.taskId) : super.fromBytes(Uint8List(0));

  /// The A2A task ID to poll.
  final String taskId;

  @override
  Uint8List toBytes() {
    final bytes = utf8.encode(jsonEncode({'taskId': taskId}));
    return Uint8List.fromList(bytes);
  }

  /// Creates an [A2AContinuationToken] from any [ResponseContinuationToken].
  ///
  /// If [token] is already an [A2AContinuationToken] it is returned as-is.
  /// Otherwise its byte payload is decoded.
  static A2AContinuationToken fromToken(ResponseContinuationToken token) {
    if (token is A2AContinuationToken) return token;

    final bytes = token.toBytes();
    if (bytes.isEmpty) {
      throw ArgumentError.value(
        token,
        'token',
        'Cannot create A2AContinuationToken: token contains no data.',
      );
    }

    try {
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final taskId = map['taskId'] as String?;
      if (taskId == null || taskId.isEmpty) {
        throw ArgumentError.value(
          token,
          'token',
          "A2AContinuationToken requires a non-empty 'taskId' property.",
        );
      }
      return A2AContinuationToken(taskId);
    } on ArgumentError {
      rethrow;
    } catch (e) {
      throw ArgumentError.value(
        token,
        'token',
        'Failed to parse A2AContinuationToken: $e',
      );
    }
  }
}

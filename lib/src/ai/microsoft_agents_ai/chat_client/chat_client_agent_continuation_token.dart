import 'dart:convert';
import 'dart:typed_data';

import 'package:extensions/ai.dart';

const String _typeDiscriminator = '__type';
const String _tokenTypeName = 'ChatClientAgentContinuationToken';

/// Represents a continuation token for [ChatClientAgent] operations that
/// carries additional context needed to resume interrupted responses.
class ChatClientAgentContinuationToken extends ResponseContinuationToken {
  /// Creates a [ChatClientAgentContinuationToken] wrapping [innerToken].
  ChatClientAgentContinuationToken(this.innerToken)
      : super.fromBytes(Uint8List(0));

  /// The continuation token provided by the underlying [ChatClient].
  final ResponseContinuationToken innerToken;

  /// Input messages used for the streaming run, if any.
  Iterable<ChatMessage>? inputMessages;

  /// Response updates received so far, if any.
  List<ChatResponseUpdate>? responseUpdates;

  @override
  Uint8List toBytes() {
    final map = <String, Object?>{
      _typeDiscriminator: _tokenTypeName,
      'innerToken': base64.encode(innerToken.toBytes()),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  /// Creates a [ChatClientAgentContinuationToken] from any
  /// [ResponseContinuationToken].
  ///
  /// If [token] is already a [ChatClientAgentContinuationToken], it is
  /// returned directly. Otherwise [token.toBytes()] is decoded.
  static ChatClientAgentContinuationToken fromToken(
    ResponseContinuationToken token,
  ) {
    if (token is ChatClientAgentContinuationToken) return token;

    final bytes = token.toBytes();
    if (bytes.isEmpty) {
      throw ArgumentError.value(
        token,
        'token',
        'Cannot create ChatClientAgentContinuationToken from an empty token.',
      );
    }

    try {
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final type = map[_typeDiscriminator] as String?;
      if (type != _tokenTypeName) {
        throw ArgumentError.value(
          token,
          'token',
          'Token is not of type $_tokenTypeName (found: $type).',
        );
      }
      final innerBytes =
          base64.decode(map['innerToken'] as String);
      final innerToken = ResponseContinuationToken.fromBytes(
        Uint8List.fromList(innerBytes),
      );
      return ChatClientAgentContinuationToken(innerToken);
    } on ArgumentError {
      rethrow;
    } catch (e) {
      throw ArgumentError.value(
        token,
        'token',
        'Failed to parse ChatClientAgentContinuationToken: $e',
      );
    }
  }
}

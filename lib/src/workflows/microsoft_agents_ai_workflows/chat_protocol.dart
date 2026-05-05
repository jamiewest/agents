import 'package:extensions/ai.dart';
import 'protocol_descriptor.dart';
import 'turn_token.dart';
import 'workflow.dart';

/// Provides extension methods for determining and enforcing whether a
/// protocol descriptor represents the Agent Workflow Chat Protocol. This is
/// defined as supporting a [List] and [TurnToken] as input. Optional support
/// for additional [ChatMessage] payloads (e.g. String, when a default role is
/// defined), or other collections of messages are optional to support.
extension ChatProtocolExtensions on ProtocolDescriptor {
  /// Determines whether the specified protocol descriptor represents the Agent
  /// Workflow Chat Protocol.
  ///
  /// Returns: `true` if the protocol descriptor represents a supported chat
  /// protocol; otherwise, `false`.
  ///
  /// [descriptor] The protocol descriptor to evaluate.
  ///
  /// [allowCatchAll] If `true`, will allow protocols handling all inputs to be
  /// treated as a Chat Protocol
  bool isChatProtocol({bool? allowCatchAll}) {
    var foundIEnumerableChatMessageInput = false;
    var foundTurnTokenInput = false;
    if (allowCatchAll && descriptor.acceptsAll) {
      return true;
    }
    for (final inputType in descriptor.accepts) {
      if (inputType == Iterable<ChatMessage>) {
        foundIEnumerableChatMessageInput = true;
      } else if (inputType == TurnToken) {
        foundTurnTokenInput = true;
      }
    }
    return foundIEnumerableChatMessageInput && foundTurnTokenInput;
  }

  /// Throws an exception if the specified protocol descriptor does not
  /// represent a valid chat protocol.
  ///
  /// [descriptor] The protocol descriptor to validate as a chat protocol.
  /// Cannot be null.
  ///
  /// [allowCatchAll] If `true`, will allow protocols handling all inputs to be
  /// treated as a Chat Protocol
  void throwIfNotChatProtocol({bool? allowCatchAll}) {
    if (!descriptor.isChatProtocol(allowCatchAll)) {
      throw StateError(
        "Workflow does not support ChatProtocol: At least List<ChatMessage>" +
            " and TurnToken must be supported as input.",
      );
    }
  }
}

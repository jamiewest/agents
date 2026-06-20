// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/AgentInvocationContext.cs.

import '../id_generator.dart';

/// Context carried through a single response invocation.
class AgentInvocationContext {
  /// Creates an [AgentInvocationContext].
  AgentInvocationContext({
    required this.idGenerator,
    required this.responseId,
    this.conversationId,
  });

  /// The ID generator scoped to this response/conversation.
  final IdGenerator idGenerator;

  /// The ID assigned to the response being produced.
  final String responseId;

  /// The conversation this response belongs to, if any.
  final String? conversationId;
}

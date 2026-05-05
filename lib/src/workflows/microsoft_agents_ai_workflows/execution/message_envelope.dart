import '../checkpointing/type_id.dart';
import 'executor_identity.dart';

class MessageEnvelope {
  MessageEnvelope(
    Object message,
    ExecutorIdentity source,
    String? targetId,
    Map<String, String>? traceContext,
    {TypeId? declaredType = null, },
  ) :
      message = message,
      source = source,
      targetId = targetId,
      traceContext = traceContext;

  TypeId get messageType {
    return declaredType ?? new(message.runtimeType);
  }

  Object get message {
    return message;
  }

  ExecutorIdentity get source {
    return source;
  }

  String? get targetId {
    return targetId;
  }

  Map<String, String>? get traceContext {
    return traceContext;
  }

  bool get isExternal {
    return this.source == ExecutorIdentity.none;
  }

  String? get sourceId {
    return this.source.id;
  }
}

import '../checkpointing/portable_message_envelope.dart';
import '../fan_in_edge_data.dart';
import 'executor_identity.dart';
import 'message_envelope.dart';

class FanInEdgeState {
  FanInEdgeState({FanInEdgeData? fanInEdge = null, List<String>? sourceIds = null, Set<String>? unseen = null, List<PortableMessageEnvelope>? pendingMessages = null, }) {
    this.sourceIds = fanInEdge.sourceIds.toList();
    this.unseen = [...this.sourceIds];
    this.pendingMessages = [];
  }

  final Object _syncLock;

  late final List<String> sourceIds;

  late Set<String> unseen;

  late List<PortableMessageEnvelope> pendingMessages;

  Iterable<Grouping<ExecutorIdentity, MessageEnvelope>>? processMessage(
    String sourceId,
    MessageEnvelope envelope,
  ) {
    var takenMessages = null;
    /* TODO: unsupported node kind "unknown" */
    // // Serialize concurrent calls from parallel executor tasks during superstep execution.
    //         // NOTE - IMPORTANT: If this ProcessMessage method ever becomes async, replace this lock with an async friendly solution to avoid deadlocks.
    //         lock (this._syncLock)
    //         {
      //             this.PendingMessages.Add(new(envelope));
      //             this.Unseen.Remove(sourceId);
      //
      //             if (this.Unseen.Count == 0)
      //             {
        //                 takenMessages = this.PendingMessages;
        //                 this.PendingMessages = [];
        //                 this.Unseen = [...this.SourceIds];
        //             }
      //         }
    if (takenMessages == null || takenMessages.length == 0) {
      return null;
    }
    return takenMessages
            .map((portable) => portable.toMessageEnvelope())
            .groupBy((messageEnvelope) => messageEnvelope.source);
  }
}

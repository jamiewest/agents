import 'edge.dart';
import 'workflow.dart';

/// A unique identifier of an [Edge] within a [Workflow].
class EdgeId {
  /// Creates an [EdgeId] for the edge at [edgeIndex].
  const EdgeId(this.edgeIndex);

  /// The zero-based position of this edge in the workflow.
  final int edgeIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is EdgeId && edgeIndex == other.edgeIndex);

  @override
  int get hashCode => edgeIndex.hashCode;

  @override
  String toString() => edgeIndex.toString();
}

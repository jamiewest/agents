import 'dart:collection';

import '../fan_out_edge_data.dart';

/// The connection structure of an edge, defined by an ordered list of source
/// and sink IDs.
///
/// Ordering matters: for [FanOutEdgeData] the sink order is significant during
/// execution. [EdgeConnection] can also serve as a unique identity for an edge.
class EdgeConnection {
  /// Creates an [EdgeConnection] with the given source and sink IDs.
  EdgeConnection(this.sourceIds, this.sinkIds);

  /// The unique identifiers of the sources connected by this edge, in order.
  final List<String> sourceIds;

  /// The unique identifiers of the sinks connected by this edge, in order.
  final List<String> sinkIds;

  /// Creates an [EdgeConnection] after validating that all IDs within each
  /// list are unique.
  static EdgeConnection createChecked(
    List<String> sourceIds,
    List<String> sinkIds,
  ) {
    final uniqueSources = LinkedHashSet<String>.from(sourceIds);
    if (uniqueSources.length != sourceIds.length) {
      throw ArgumentError.value(sourceIds, 'sourceIds', 'Source IDs must be unique.');
    }
    final uniqueSinks = LinkedHashSet<String>.from(sinkIds);
    if (uniqueSinks.length != sinkIds.length) {
      throw ArgumentError.value(sinkIds, 'sinkIds', 'Sink IDs must be unique.');
    }
    return EdgeConnection(sourceIds, sinkIds);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EdgeConnection) return false;
    if (sourceIds.length != other.sourceIds.length) return false;
    if (sinkIds.length != other.sinkIds.length) return false;
    for (var i = 0; i < sourceIds.length; i++) {
      if (sourceIds[i] != other.sourceIds[i]) return false;
    }
    for (var i = 0; i < sinkIds.length; i++) {
      if (sinkIds[i] != other.sinkIds[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = 0;
    for (final id in sourceIds) {
      hash = Object.hash(hash, id);
    }
    for (final id in sinkIds) {
      hash = Object.hash(hash, id);
    }
    return Object.hash(sourceIds.length, sinkIds.length, hash);
  }

  @override
  String toString() =>
      '[${sourceIds.join(',')}] => [${sinkIds.join(',')}]';
}

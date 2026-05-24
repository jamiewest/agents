import 'direct_edge_info.dart';
import 'fan_in_edge_info.dart';
import 'fan_out_edge_info.dart';

/// Serializable workflow edge information.
abstract class EdgeInfo {
  /// Creates edge info.
  const EdgeInfo({required this.edgeId, required this.kind});

  /// Gets the edge identifier.
  final String edgeId;

  /// Gets the edge kind discriminator.
  final String kind;

  /// Gets source executor identifiers.
  Iterable<String> get sourceExecutorIds;

  /// Gets target executor identifiers.
  Iterable<String> get targetExecutorIds;

  /// Converts this edge info to JSON.
  Map<String, Object?> toJson();

  /// Creates edge info from JSON.
  static EdgeInfo fromJson(Map<String, Object?> json) {
    final kind = json['kind']! as String;
    return switch (kind) {
      'direct' => DirectEdgeInfo.fromJson(json),
      'fanOut' => FanOutEdgeInfo.fromJson(json),
      'fanIn' => FanInEdgeInfo.fromJson(json),
      _ => throw ArgumentError.value(kind, 'kind', 'Unknown edge kind.'),
    };
  }
}

/// Converts a JSON list into a string list.
List<String> checkpointStringList(Object? value) =>
    (value as List? ?? const <Object?>[]).cast<String>();

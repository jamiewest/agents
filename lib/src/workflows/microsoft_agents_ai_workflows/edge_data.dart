import 'edge_id.dart';
import 'execution/edge_connection.dart';

/// A base class for edge data, providing access to the [EdgeConnection]
/// representation of the edge.
abstract class EdgeData {
  EdgeData(EdgeId id, {String? label = null}) : id = id {
    this.label = label;
  }

  /// Gets the connection representation of the edge.
  final EdgeConnection connection;

  final EdgeId id;

  /// An optional label for the edge, allowing for arbitrary metadata to be
  /// associated with it.
  late final String? label;
}

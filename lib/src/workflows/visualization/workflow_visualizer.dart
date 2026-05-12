import '../direct_edge_data.dart';
import '../fan_in_edge_data.dart';
import '../fan_out_edge_data.dart';
import '../workflow.dart';

/// Generates visual representations of a [Workflow].
final class WorkflowVisualizer {
  const WorkflowVisualizer._();

  /// Generates a Mermaid `flowchart LR` definition for [workflow].
  ///
  /// Executor IDs become nodes; edges are rendered as directed arrows.
  static String toMermaid(Workflow workflow) {
    final buf = StringBuffer('flowchart LR\n');

    for (final binding in workflow.reflectExecutors()) {
      final safe = _safeId(binding.id);
      buf.writeln('  $safe["${binding.id}"]');
    }

    for (final edge in workflow.reflectEdges()) {
      final data = edge.data;
      if (data is DirectEdgeData) {
        final label =
            data.messageType != null ? ' |${data.messageType}|' : '';
        buf.writeln(
          '  ${_safeId(data.sourceExecutorId)} -->'
          '$label ${_safeId(data.targetExecutorId)}',
        );
      } else if (data is FanOutEdgeData) {
        for (final target in data.targetExecutorIds) {
          buf.writeln(
            '  ${_safeId(data.sourceExecutorId)} --> ${_safeId(target)}',
          );
        }
      } else if (data is FanInEdgeData) {
        for (final source in data.sourceExecutorIds) {
          buf.writeln(
            '  ${_safeId(source)} --> ${_safeId(data.targetExecutorId)}',
          );
        }
      }
    }

    return buf.toString();
  }

  static String _safeId(String id) => id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
}

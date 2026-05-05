import '../workflow.dart';

/// Provides visualization utilities for workflows using Graphviz DOT format.
extension WorkflowVisualizer on Workflow {
  /// Export the workflow as a DOT format digraph String.
  ///
  /// Returns: A String representation of the workflow in DOT format.
  String toDotString() {
    var lines = List<String>();
    // Emit the top-level workflow nodes/edges
    emitWorkflowDigraph(workflow, lines, "  ");
    // Emit sub-workflows hosted by WorkflowExecutor as nested clusters
    emitSubWorkflowsDigraph(workflow, lines, "  ");
    lines.add("}");
    return lines.join("\n");
  }

  /// Converts the specified [Workflow] into a Mermaid.js diagram
  /// representation.
  ///
  /// Remarks: This method generates a textual representation of the workflow in
  /// the Mermaid.js format, which can be used to visualize workflows as
  /// diagrams. The output is formatted with indentation for readability.
  ///
  /// Returns: A String containing the Mermaid.js representation of the
  /// workflow.
  ///
  /// [workflow] The workflow to be converted into a Mermaid.js diagram. Cannot
  /// be null.
  String toMermaidString() {
    var lines = ["flowchart TD"];
    emitWorkflowMermaid(workflow, lines, "  ");
    return lines.join("\n");
  }
}

import '../workflow.dart';

/// Decides whether an executor is authorised to emit workflow output.
final class OutputFilter {
  /// Creates an [OutputFilter] for [workflow].
  OutputFilter(this._workflow);

  final Workflow _workflow;

  /// Returns `true` when [sourceExecutorId] is a declared output executor.
  bool canOutput(String sourceExecutorId, Object output) =>
      _workflow.reflectOutputExecutors().contains(sourceExecutorId);
}

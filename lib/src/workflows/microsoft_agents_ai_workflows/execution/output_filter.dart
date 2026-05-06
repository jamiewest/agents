import '../workflow.dart';

class OutputFilter {
  const OutputFilter(this.workflow);

  final Workflow workflow;

  bool canOutput(String sourceExecutorId, Object output) {
    return workflow.outputExecutors.contains(sourceExecutorId);
  }
}

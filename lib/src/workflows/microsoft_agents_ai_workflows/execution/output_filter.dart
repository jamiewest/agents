import '../workflow.dart';

class OutputFilter {
  const OutputFilter(Workflow workflow);

  bool canOutput(String sourceExecutorId, Object output) {
    return workflow.outputExecutors.contains(sourceExecutorId);
  }
}

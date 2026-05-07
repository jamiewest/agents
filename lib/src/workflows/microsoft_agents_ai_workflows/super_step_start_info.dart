/// Debug information about the SuperStep starting to run.
class SuperStepStartInfo {
  /// Creates super-step start info.
  SuperStepStartInfo(
    Iterable<String> sendingExecutors, {
    this.hasExternalMessages = false,
  }) : sendingExecutors = List<String>.unmodifiable(sendingExecutors);

  /// Gets executor IDs that sent messages during the previous SuperStep.
  final List<String> sendingExecutors;

  /// Gets whether external messages were queued during the previous SuperStep.
  final bool hasExternalMessages;
}

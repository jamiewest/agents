/// Debug information about the SuperStep starting to run.
class SuperStepStartInfo {
  /// Debug information about the SuperStep starting to run.
  SuperStepStartInfo({Set<String>? sendingExecutors})
      : sendingExecutors = sendingExecutors ?? {};

  /// The unique identifiers of [Executor] instances that sent messages during
  /// the previous SuperStep.
  final Set<String> sendingExecutors;

  /// Gets a value indicating whether there are any external messages queued
  /// during the previous SuperStep.
  bool hasExternalMessages = false;
}

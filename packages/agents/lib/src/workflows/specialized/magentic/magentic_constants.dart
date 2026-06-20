/// State keys used by the Magentic orchestrator when checkpointing.
abstract final class MagenticConstants {
  /// Scoped state key under which the Magentic task context is stored.
  static const String magenticTaskContextKey = 'MagenticTaskContextKey';

  /// Scoped state key under which the current speaker executor id is stored.
  static const String currentSpeakerStateKey = 'CurrentSpeakerStateKey';
}

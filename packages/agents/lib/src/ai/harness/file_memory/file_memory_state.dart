import '../../../abstractions/agent_session_state_bag.dart';
import 'file_memory_provider.dart';

/// Represents the state of the [FileMemoryProvider], stored in the session's
/// [AgentSessionStateBag].
class FileMemoryState {
  FileMemoryState();

  /// Working folder path for this session, relative to the store root.
  String workingFolder = '';

  /// Encodes this state to a JSON-compatible map so the session bag can
  /// serialize it.
  Map<String, Object?> toJson() => {'workingFolder': workingFolder};

  /// Rebuilds the state from a raw JSON-decoded value produced by [toJson].
  static FileMemoryState fromJson(Object? json) {
    final state = FileMemoryState();
    if (json is Map) {
      state.workingFolder = json['workingFolder'] as String? ?? '';
    }
    return state;
  }
}

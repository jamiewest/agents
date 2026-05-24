import '../../../abstractions/agent_session_state_bag.dart';
import 'file_memory_provider.dart';

/// Represents the state of the [FileMemoryProvider], stored in the session's
/// [AgentSessionStateBag].
class FileMemoryState {
  FileMemoryState();

  /// Working folder path for this session, relative to the store root.
  String workingFolder = '';
}

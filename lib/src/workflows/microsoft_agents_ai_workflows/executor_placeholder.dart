import 'executor_binding.dart';

/// Represents a placeholder entry for an [ExecutorBinding], identified by a
/// unique ID.
///
/// [Id] The unique identifier for the placeholder registration.
class ExecutorPlaceholder extends ExecutorBinding {
  /// Represents a placeholder entry for an [ExecutorBinding], identified by a
  /// unique ID.
  ///
  /// [Id] The unique identifier for the placeholder registration.
  const ExecutorPlaceholder(String Id);

  bool get supportsConcurrentSharedExecution {
    return false;
  }

  bool get supportsResetting {
    return false;
  }

  bool get isSharedInstance {
    return false;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExecutorPlaceholder;
  }

  @override
  int get hashCode {
    return runtimeType.hashCode;
  }
}

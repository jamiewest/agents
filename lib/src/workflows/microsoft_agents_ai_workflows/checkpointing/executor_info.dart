/// Serializable executor registration information.
class ExecutorInfo {
  /// Creates executor info.
  const ExecutorInfo({
    required this.executorId,
    this.typeName,
    this.supportsConcurrentSharedExecution = true,
    this.supportsResetting = false,
  });

  /// Gets the executor identifier.
  final String executorId;

  /// Gets the executor type name, when available.
  final String? typeName;

  /// Gets whether this executor supports concurrent shared execution.
  final bool supportsConcurrentSharedExecution;

  /// Gets whether this executor supports reset.
  final bool supportsResetting;

  /// Converts this info to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'executorId': executorId,
    if (typeName != null) 'typeName': typeName,
    'supportsConcurrentSharedExecution': supportsConcurrentSharedExecution,
    'supportsResetting': supportsResetting,
  };

  /// Creates executor info from JSON.
  factory ExecutorInfo.fromJson(Map<String, Object?> json) => ExecutorInfo(
    executorId: json['executorId']! as String,
    typeName: json['typeName'] as String?,
    supportsConcurrentSharedExecution:
        json['supportsConcurrentSharedExecution'] as bool? ?? true,
    supportsResetting: json['supportsResetting'] as bool? ?? false,
  );
}

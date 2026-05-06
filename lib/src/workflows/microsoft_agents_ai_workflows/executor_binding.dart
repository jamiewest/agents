import '../../func_typedefs.dart';
import 'executor.dart';
import 'identified.dart';
import 'workflow.dart';

/// Represents the binding information for a workflow executor, including its
/// identifier, factory method, type, and optional raw value.
///
/// [Id] The unique identifier for the executor in the workflow.
///
/// [FactoryAsync] A factory function that creates an instance of the
/// executor. The function accepts two String parameters and returns a
/// ValueTask containing the created Executor instance.
///
/// [ExecutorType] The type of the executor. Must be a type derived from
/// Executor.
///
/// [RawValue] An optional raw value associated with the binding.
abstract class ExecutorBinding implements Identified {
  /// Represents the binding information for a workflow executor, including its
  /// identifier, factory method, type, and optional raw value.
  ///
  /// [Id] The unique identifier for the executor in the workflow.
  ///
  /// [FactoryAsync] A factory function that creates an instance of the
  /// executor. The function accepts two String parameters and returns a
  /// ValueTask containing the created Executor instance.
  ///
  /// [ExecutorType] The type of the executor. Must be a type derived from
  /// Executor.
  ///
  /// [RawValue] An optional raw value associated with the binding.
  ExecutorBinding(
    String Id,
    Func<String, Future<Executor>>? FactoryAsync,
    Type ExecutorType,
    {Object? RawValue = null, }
  ) :
      id = Id,
      factoryAsync = FactoryAsync,
      executorType = ExecutorType;

  /// The unique identifier for the executor in the workflow.
  String id;

  /// A factory function that creates an instance of the executor. The function
  /// accepts two String parameters and returns a ValueTask containing the
  /// created Executor instance.
  Func<String, Future<Executor>>? factoryAsync;

  /// The type of the executor. Must be a type derived from Executor.
  Type executorType;

  /// An optional raw value associated with the binding.
  Object? rawValue;

  /// Gets a value whether the executor created from this binding is a shared
  /// instance across all runs.
  final bool isSharedInstance;

  /// Gets a value whether instances of the executor created from this binding
  /// can be used in concurrent runs from the same [Workflow] instance.
  final bool supportsConcurrentSharedExecution;

  /// Gets a value whether instances of the executor created from this binding
  /// can be reset between subsequent runs from the same [Workflow] instance.
  /// This value is not relevant for executors that
  /// [SupportsConcurrentSharedExecution].
  final bool supportsResetting;

  /// Gets a value indicating whether the binding is a placeholder (i.e., does
  /// not have a factory method defined).
  bool get isPlaceholder {
    return this.factoryAsync == null;
  }

  @override
  String toString() {
    return '${this.id}:${(this.isPlaceholder ? ":<unbound>" : this.executorType.name)}';
  }

  Executor checkId(Executor executor) {
    if (executor.id != this.id) {
      throw StateError(
                'Executor ID mismatch: expected ${this.id}, but got "${executor.id}".');
    }
    return executor;
  }

  Future<Executor> createInstance(String sessionId) async {
    return !this.isPlaceholder
         ? this.checkId(await this.factoryAsync(sessionId))
         : throw StateError(
                "Cannot create executor with ID ${this.id}: binding(${this.runtimeType.toString()}) is a placeholder.");
  }

  @override
  bool equals({ExecutorBinding? other}) {
    return other != null && other.id == this.id;
  }

  Future<bool> tryReset() {
    if (!this.isSharedInstance) {
      return new(true);
    }
    if (!this.supportsResetting) {
      return new(false);
    }
    return this.resetCore();
  }

  /// Resets the executor's shared resources to their initial state. Must be
  /// overridden by bindings that support resetting.
  Future<bool> resetCore() {
    return throw StateError("ExecutorBindings that support resetting must override resetCoreAsync()");
  }

  @override
  int hashCode {
    return this.id.hashCode;
  }

  @override
  bool operator ==(Object other) { if (identical(this, other)) return true;
    return other is ExecutorBinding &&
    id == other.id &&
    factoryAsync == other.factoryAsync &&
    executorType == other.executorType &&
    rawValue == other.rawValue &&
    isSharedInstance == other.isSharedInstance &&
    supportsConcurrentSharedExecution == other.supportsConcurrentSharedExecution &&
    supportsResetting == other.supportsResetting; }
  @override
  int get hashCode { return Object.hash(
    id,
    factoryAsync,
    executorType,
    rawValue,
    isSharedInstance,
    supportsConcurrentSharedExecution,
    supportsResetting,
  ); }
}

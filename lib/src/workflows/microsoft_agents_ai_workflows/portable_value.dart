import 'checkpointing/delayed_deserialization.dart';
import 'checkpointing/type_id.dart';

/// A value that can be exported/imported through a workflow, supporting lazy
/// deserialization and type conversion.
class PortableValue {
  /// Creates a [PortableValue] wrapping [value], with an automatically derived
  /// [TypeId] based on [value]'s runtime type.
  PortableValue(Object value)
      : _value = value,
        _deserializedValueCache = null,
        typeId = TypeId(
          assemblyName: '',
          typeName: value.runtimeType.toString(),
        );

  /// Creates a [PortableValue] with an explicit [typeId].
  PortableValue.typed(Object value, this.typeId)
      : _value = value,
        _deserializedValueCache = null;

  /// The type identity of the value.
  final TypeId typeId;

  final Object _value;
  Object? _deserializedValueCache;

  /// Whether the underlying value supports delayed (lazy) deserialization.
  bool get isDelayedDeserialization => _value is DelayedDeserialization;

  /// Whether the value has already been deserialized and cached.
  bool get isDeserialized => _deserializedValueCache != null;

  /// The effective value — returns the deserialized cache if available,
  /// otherwise the raw underlying value.
  Object get value => _deserializedValueCache ?? _value;

  /// Attempts to return the underlying value cast to [TValue], deserializing
  /// if necessary. Returns `null` if the cast or deserialization fails.
  TValue? as_<TValue>() {
    final (success, val) = isValue<TValue>();
    return success ? val : null;
  }

  /// Returns whether the value can be represented as [TValue], and if so
  /// provides it.
  (bool, TValue?) isValue<TValue>() {
    _tryDeserializeAndUpdateCache(TValue);
    final v = value;
    if (v is TValue) return (true, v as TValue);
    return (false, null);
  }

  /// Attempts to return the underlying value cast to [targetType], deserializing
  /// if necessary. Returns `null` if unavailable.
  Object? asType(Type targetType) {
    final (success, val) = isType(targetType);
    return success ? val : null;
  }

  /// Returns whether the value can be represented as [targetType], and if so
  /// provides it.
  (bool, Object?) isType(Type targetType) {
    _tryDeserializeAndUpdateCache(targetType);
    final v = value;
    if (v.runtimeType == targetType || targetType == Object) {
      return (true, v);
    }
    return (false, null);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PortableValue) return false;
    if (typeId != other.typeId) return false;
    return value == other.value;
  }

  @override
  int get hashCode => Object.hash(typeId, value);

  /// Attempts to deserialize the underlying value to [targetType] and cache
  /// the result. Returns `(true, previousCache)` if the cache was replaced.
  (bool, Object?) _tryDeserializeAndUpdateCache(Type targetType) {
    if (_value is! DelayedDeserialization) return (false, null);
    final delayed = _value as DelayedDeserialization; // narrowed by is-check above

    final cached = _deserializedValueCache;
    if (cached != null && cached.runtimeType == targetType) {
      return (false, null);
    }

    try {
      final deserialized = delayed.deserialize(targetType: targetType);
      if (deserialized != null) {
        final previous = _deserializedValueCache;
        _deserializedValueCache = deserialized;
        return (true, previous);
      }
    } catch (_) {
      // Deserialization failed; leave cache unchanged.
    }
    return (false, null);
  }
}

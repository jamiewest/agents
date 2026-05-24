import 'package:extensions/ai.dart';

/// Extension methods for [AdditionalPropertiesDictionary] that use the
/// runtime type name of [T] as the dictionary key.
extension AdditionalPropertiesExtensions on AdditionalPropertiesDictionary {
  /// Adds [value] using the runtime type name of [T] as the key.
  void addTyped<T>(T value) {
    this[T.toString()] = value;
  }

  /// Attempts to add [value] using the type name of [T] as the key.
  ///
  /// Returns `true` if added; `false` if the key already exists.
  bool tryAdd<T>(T value) {
    final key = T.toString();
    if (containsKey(key)) return false;
    this[key] = value;
    return true;
  }

  /// Attempts to retrieve a value of type [T] using the type name as the key.
  ///
  /// Returns `true` and sets [value] if found; otherwise returns `false`.
  (bool, T?) tryGetTyped<T>() {
    final key = T.toString();
    final v = this[key];
    if (v is T) return (true, v);
    return (false, null);
  }

  /// Returns `true` if the dictionary contains a key equal to the type name
  /// of [T].
  bool containsType<T>() => containsKey(T.toString());

  /// Removes the entry whose key equals the type name of [T].
  ///
  /// Returns `true` if the entry was removed; otherwise `false`.
  bool removeType<T>() => remove(T.toString()) != null;
}

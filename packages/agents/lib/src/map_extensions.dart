/// Extension methods to port .NET ConcurrentDictionary / Dictionary patterns
/// to Dart's Map API.
extension MapTryExtensions<K, V> on Map<K, V> {
  /// Returns `true` and adds [key]/[value] if [key] is not already present.
  /// Mirrors ConcurrentDictionary.TryAdd.
  bool tryAdd(K key, V value) {
    if (containsKey(key)) return false;
    this[key] = value;
    return true;
  }

  /// Removes [key] and returns `true` if it was present.
  /// Mirrors Dictionary.TryRemove / ConcurrentDictionary.TryRemove.
  bool tryRemoveKey(K key) => remove(key) != null;

  /// Returns the value for [key] if present, or `null` if absent.
  /// Mirrors Dictionary.TryGetValue — call as `final v = map.tryGetValue(k)`.
  V? tryGetValue(K key) => this[key];
}

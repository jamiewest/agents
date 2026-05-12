/// An immutable record of a single state change — either an upsert or a
/// deletion.
class StateUpdate {
  StateUpdate._(this.key, this.value, this.isDelete)
      : assert(key.isNotEmpty, 'key must not be empty');

  /// Creates an upsert update; if [value] is `null` it becomes a delete.
  static StateUpdate update<T>(String key, T? value) =>
      StateUpdate._(key, value, value == null);

  /// Creates a deletion update for [key].
  static StateUpdate delete(String key) =>
      StateUpdate._(key, null, true);

  /// The state key being updated.
  final String key;

  /// The new value, or `null` for deletions.
  final Object? value;

  /// Whether this update is a deletion.
  final bool isDelete;
}

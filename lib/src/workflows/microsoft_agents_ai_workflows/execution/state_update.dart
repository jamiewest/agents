class StateUpdate {
  StateUpdate(String key, Object? value, {bool isDelete = false})
      : key = key,
        value = value,
        isDelete = isDelete;

  final String key;

  final Object? value;

  final bool isDelete;

  static StateUpdate update<T>(String key, T? value) {
    return StateUpdate(key, value, isDelete: value == null);
  }

  static StateUpdate delete(String key) {
    return StateUpdate(key, null, isDelete: true);
  }
}

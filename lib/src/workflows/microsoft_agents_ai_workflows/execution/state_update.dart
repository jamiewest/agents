class StateUpdate {
  StateUpdate(String key, Object? value, {bool? isDelete = null, }) : key = key, value = value {
    this.isDelete = isDelete;
  }

  final String key;

  final Object? value;

  late final bool isDelete;

  static StateUpdate update<T>(String key, T? value, ) {
    return new(key, value, value == null);
  }

  static StateUpdate delete(String key) {
    return stateUpdate(key, null, isDelete: true);
  }
}

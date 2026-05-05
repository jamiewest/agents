import '../portable_value.dart';
import '../scope_id.dart';
import 'state_update.dart';

class StateScope {
  StateScope({ScopeId? scopeId = null, String? executor = null, String? scopeName = null, }) {
    this.scopeId = scopeId;
  }

  final Map<String, PortableValue> _stateData = {};

  late final ScopeId scopeId;

  Future<Set<String>> readKeys() {
    var keys = new(this._stateData.keys, this._stateData.comparer);
    return new(keys);
  }

  bool contains<T>(String key) {
    PortableValue value;
    if (this._stateData.containsKey(key)) {
      return value.isValue<T>();
    }
    return false;
  }

  bool containsKey(String key) {
    return this._stateData.containsKey(key);
  }

  Future<T?> readState<T>(String key) {
    PortableValue value;
    if (this._stateData.containsKey(key)) {
      if (T == PortableValue && !value.typeId.isMatch<PortableValue>()) {
        return new((T)(Object)value);
      }
      return new(value.as<T>());
    }
    return new((T?)default);
  }

  Future writeState(Map<String, List<StateUpdate>> updates) {
    for (final key in updates.keys) {
      if (updates == null || updates[key].length == 0) {
        continue;
      }
      if (updates[key].length > 1) {
        throw StateError("Expected exactly one update for key ${key}.");
      }
      var update = updates[key][0];
      if (update.isDelete) {
        this._stateData.remove(key);
      } else {
        this._stateData[key] = PortableValue(update.value!);
      }
    }
    return Future.value();
  }

  Iterable<MapEntry<String, PortableValue>> exportStates() {
    return this._stateData.keys.map(WrapStates);
    /* TODO: unsupported node kind "unknown" */
    // KeyValuePair<String, PortableValue> WrapStates(String key)
    //         {
      //             return new(key, this._stateData[key]);
      //         }
  }

  void importState(String key, PortableValue state, ) {
    this._stateData[key] = state;
  }
}

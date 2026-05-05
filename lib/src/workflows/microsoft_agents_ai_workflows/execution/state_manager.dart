import '../checkpointing/checkpoint.dart';
import '../portable_value.dart';
import '../scope_id.dart';
import '../scope_key.dart';
import 'state_scope.dart';
import 'state_update.dart';
import 'step_tracer.dart';
import 'update_key.dart';
import '../../../map_extensions.dart';

class StateManager {
  StateManager();

  final Map<ScopeId, StateScope> _scopes = {};

  final Map<UpdateKey, StateUpdate> _queuedUpdates = {};

  StateScope getOrCreateScope(ScopeId scopeId) {
    StateScope scope;
    if (!this._scopes.containsKey(scopeId)) {
      scope = stateScope(scopeId);
      this._scopes[scopeId] = scope;
    }
    return scope;
  }

  Iterable<UpdateKey> getUpdatesForScopeStrict(ScopeId scopeId) {
    return this._queuedUpdates.keys.where((key) => key.isMatchingScope(scopeId, strict: true));
  }

  Future clearState({String? executorId, String? scopeName, ScopeId? scopeId, String? key, }) async  {
    // TODO(ai): implement dispatch
    throw UnimplementedError();
  }

  Set<String> applyUnpublishedUpdates(ScopeId scopeId, Set<String> keys, ) {
    for (final key in this.getUpdatesForScopeStrict(scopeId)) {
      var update = this._queuedUpdates[key];
      if (update.isDelete) {
        keys.remove(update.key);
      } else {
        // Add is idempotent on Sets
                keys.add(update.key);
      }
    }
    return keys;
  }

  Future<Set<String>> readKeys({String? executorId, String? scopeName, ScopeId? scopeId, }) async  {
    return this.readKeysAsync(scopeId(executorId, scopeName));
  }

  Future<T?> readState<T>(String key, {String? executorId, String? scopeName, ScopeId? scopeId, }) {
    return this.readStateAsync<T>(scopeId(executorId, scopeName), key);
  }

  Future<T> readOrInitState<T>(
    String key,
    T Function() initialStateFactory,
    {String? executorId, String? scopeName, ScopeId? scopeId, },
  ) async  {
    return this.readOrInitStateAsync(
      scopeId(executorId, scopeName),
      key,
      initialStateFactory,
    );
  }

  Future<T?> readValueOrDefault<T>(
    ScopeId scopeId,
    String key,
    {T Function()? defaultValueFactory, bool? initOnDefault, },
  ) async  {
    if (T == Object) {
      throw UnsupportedError("Reading state as 'Object' is! supported. Use 'PortableValue' instead for variants.");
    }
    var stateKey = new(scopeId, key);
    var result = defaultValueFactory != null ? defaultValueFactory() : default;
    var needsInit = false;
    StateUpdate update;
    if (this._queuedUpdates.containsKey(stateKey)) {
      if (update.isDelete || update.value == null) {
        needsInit = initOnDefault;
      } else if (update.value is T) {
        final typed = update.value as T;
        result = typed;
      } else if (T == PortableValue && update.value != null) {
        result = (T)(Object)PortableValue(update.value);
      } else {
        throw StateError("State for key ${key} in scope "${scopeId}" is! of type ${T.name}.");
      }
    } else {
      var scope = this.getOrCreateScope(scopeId);
      if (scope.containsKey(key)) {
        result = await scope.readStateAsync<T>(key);
      } else if (initOnDefault) {
        needsInit = true;
      }
    }
    if (needsInit) {
      if (defaultValueFactory == null) {
        throw ArgumentError.notNull(
          'defaultValueFactory',
          "Default value must be provided when initializing state.",
        );
      }
      assert(initOnDefault);
      await this.writeStateAsync(scopeId, key, defaultValueFactory());
    }
    return result;
  }

  Future writeState<T>(
    String key,
    T value,
    {String? executorId, String? scopeName, ScopeId? scopeId, },
  ) {
    return this.writeStateAsync(scopeId(executorId, scopeName), key, value);
  }

  Future publishUpdates(StepTracer? tracer) async  {
    var updatesByScope = [];
    for (final key in this._queuedUpdates.keys) {
      if (!updatesByScope.tryGetValue(key.scopeId)) {
        updatesByScope[key.scopeId] = scopeUpdates = [];
      }
      List<StateUpdate>? stateUpdates;
      if (!scopeUpdates.containsKey(key.key)) {
        scopeUpdates[key.key] = stateUpdates = [];
      }
      stateUpdates.add(this._queuedUpdates[key]);
    }
    if (tracer != null && (updatesByScope.length > 0)) {
      tracer.traceStatePublished();
    }
    for (final scope in updatesByScope.keys) {
      var stateScope = this.getOrCreateScope(scope);
      await stateScope.writeStateAsync(updatesByScope[scope]);
    }
    this._queuedUpdates.clear();
  }

  static Iterable<MapEntry<ScopeKey, PortableValue>> exportScope(StateScope scope) {
    for (final state in scope.exportStates()) {
      yield new(scopeKey(scope.scopeId, state.key), state.value);
    }
  }

  Future<Map<ScopeKey, PortableValue>> exportState() async  {
    if (this._queuedUpdates.length != 0) {
      throw StateError("Cannot export state while there are queued updates. Call publishUpdatesAsync() first.");
    }
    return this._scopes.values.expand(ExportScope).toDictionary((kvp) => kvp.key, (kvp) => kvp.value);
  }

  Future importState(Checkpoint checkpoint) {
    if (this._queuedUpdates.length != 0) {
      throw StateError("Cannot import state while there are queued updates. Call publishUpdatesAsync() first.");
    }
    this._queuedUpdates.clear();
    this._scopes.clear();
    var importedState = checkpoint.stateData;
    for (final scopeKey in importedState.keys) {
      var scope = this.getOrCreateScope(scopeKey.scopeId);
      scope.importState(scopeKey.key, importedState[scopeKey]);
    }
    return Future.value();
  }
}

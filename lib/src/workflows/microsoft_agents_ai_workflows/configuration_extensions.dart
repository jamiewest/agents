/// Provides extension methods for creating [Configured] objects
extension ConfigurationExtensions on Configured<TSubject> {
  /// Creates a new configuration that treats the subject as its base type,
/// allowing configuration to be applied at the parent type level.
///
/// Returns: A new [Configured] instance that applies the original
/// configuration logic to the parent type.
///
/// [configured] The existing configuration for the subject type to be upcast
/// to its parent type. Cannot be null.
///
/// [TSubject] The type of the original subject being configured. Must inherit
/// from or implement TParent.
///
/// [TParent] The base type or interface to which the configuration will be
/// upcast.
Configured<TParent> superValue<TSubject>() {
return new(
  async (config, sessionId) => await configured.factoryAsync(config, sessionId),
  configured.id,
  configured.raw,
);
 }
 }

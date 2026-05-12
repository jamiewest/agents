import 'configured.dart';

/// Extension methods for upcasting [Configured] values.
extension ConfigurationExtensions<TSubject> on Configured<TSubject> {
  /// Returns a new [Configured] whose subject is cast to [TParent].
  ///
  /// The caller is responsible for ensuring [TSubject] is a subtype of
  /// [TParent].
  Configured<TParent> asParent<TParent>() =>
      Configured<TParent>(value as TParent, config);
}

import '../../func_typedefs.dart';
import 'identified.dart';

/// Provides methods for creating [Configured] instances.
class Configured {
  Configured();

  /// Creates a [Configured] instance from an existing subject instance.
  ///
  /// Returns:
  ///
  /// [subject] The subject instance. If the subject implements [Identified],
  /// its ID will be used and checked against the provided ID (if any).
  ///
  /// [id] A unique identifier for the configured subject. This is required if
  /// the subject does not implement [Identified]
  ///
  /// [raw] The raw representation of the subject instance.
  static Configured<TSubject> fromInstance<TSubject>(
    TSubject subject,
    {String? id, Object? raw, },
  ) {
    if (subject is Identified) {
      final identified = subject as Identified;
      if (id != null && identified.id != id) {
        throw ArgumentError(
          "Provided ID $id does not match subject's ID '${identified.id}'.",
          'id',
        );
      }
      return Configured<TSubject>((_, __) => new(subject), id: identified.id, raw: raw ?? subject);
    }
    if (id == null) {
      throw ArgumentError.notNull(
        'id',
        "ID must be provided when the subject does not implement IIdentified.",
      );
    }
    return Configured<TSubject>((_, __) => new(subject), id, raw: raw ?? subject);
  }
}
/// A representation of a preconfigured, lazy-instantiatable instance of
/// `TSubject`.
///
/// [factoryAsync] A factory to instantiate the subject when desired.
///
/// [id] The unique identifier for the configured subject.
///
/// [options] Additional configuration options for the subject.
///
/// [raw]
///
/// [TSubject] The type of the preconfigured subject.
///
/// [TOptions] The type of configuration options for the preconfigured
/// subject.
class Configured<TSubject,TOptions> {
  /// A representation of a preconfigured, lazy-instantiatable instance of
  /// `TSubject`.
  ///
  /// [factoryAsync] A factory to instantiate the subject when desired.
  ///
  /// [id] The unique identifier for the configured subject.
  ///
  /// [options] Additional configuration options for the subject.
  ///
  /// [raw]
  ///
  /// [TSubject] The type of the preconfigured subject.
  ///
  /// [TOptions] The type of configuration options for the preconfigured
  /// subject.
  Configured(
    Func2<ExecutorConfig<TOptions>, String, Future<TSubject>> factoryAsync,
    String id,
    {TOptions? options = null, Object? raw = null, },
  ) :
      factoryAsync = factoryAsync,
      id = id;

  /// The raw representation of the configured Object, if any.
  Object? get raw {
    return raw;
  }

  /// Gets the configured identifier for the subject.
  String get id {
    return id;
  }

  /// Gets the options associated with this instance.
  TOptions? get options {
    return options;
  }

  /// Gets the factory function to create an instance of `TSubject` given a
  /// [ExecutorConfig].
  Func2<ExecutorConfig<TOptions>, String, Future<TSubject>> get factoryAsync {
    return factoryAsync;
  }

  /// The configuration for this configured instance.
  ExecutorConfig<TOptions> get configuration {
    return new(this.id, this.options);
  }

  /// Gets a "partially" applied factory function that only requires no
  /// parameters to create an instance of `TSubject` with the provided
  /// [Configuration] instance.
  Func<String, Future<TSubject>> get boundFactoryAsync {
    return (sessionId) => this.createValidatingMemoizedFactory()(this.configuration, sessionId);
  }

  Func2<ExecutorConfig, String, Future<TSubject>> createValidatingMemoizedFactory() {
    return factoryAsync;
    /* TODO: unsupported node kind "unknown" */
    // async ValueTask<TSubject> FactoryAsync(ExecutorConfig configuration, String sessionId)
    //         {
      //             if (this.Id != configuration.Id)
      //             {
        //                 throw new InvalidOperationException($"Requested instance ID '{configuration.Id}' does not match configured ID '{this.Id}'.");
        //             }
      //
      //             TSubject subject = await this.FactoryAsync(this.Configuration, sessionId);
      //
      //             if (this.Id is not null && subject is IIdentified identified && identified.Id != this.Id)
      //             {
        //                 throw new InvalidOperationException($"Created instance ID '{identified.Id}' does not match configured ID '{this.Id}'.");
        //             }
      //
      //             return subject;
      //         }
  }

  /// Memoizes and erases the typed configuration options for the subject.
  Configured<TSubject> memoize() {
    return new(this.createValidatingMemoizedFactory(), this.id);
  }
}
/// A representation of a preconfigured, lazy-instantiatable instance of
/// `TSubject`.
///
/// [factoryAsync] A factory to instantiate the subject when desired.
///
/// [id] The unique identifier for the configured subject.
///
/// [raw]
///
/// [TSubject] The type of the preconfigured subject.
class Configured<TSubject> {
  /// A representation of a preconfigured, lazy-instantiatable instance of
  /// `TSubject`.
  ///
  /// [factoryAsync] A factory to instantiate the subject when desired.
  ///
  /// [id] The unique identifier for the configured subject.
  ///
  /// [raw]
  ///
  /// [TSubject] The type of the preconfigured subject.
  Configured(
    Func2<ExecutorConfig, String, Future<TSubject>> factoryAsync,
    String id,
    {Object? raw = null, },
  ) :
      factoryAsync = factoryAsync,
      id = id;

  /// Gets the raw representation of the configured Object, if any.
  Object? get raw {
    return raw;
  }

  /// Gets the configured identifier for the subject.
  String get id {
    return id;
  }

  /// Gets the factory function to create an instance of `TSubject` given a
  /// [ExecutorConfig].
  Func2<ExecutorConfig, String, Future<TSubject>> get factoryAsync {
    return factoryAsync;
  }

  /// The configuration for this configured instance.
  ExecutorConfig get configuration {
    return new(this.id);
  }

  /// Gets a "partially" applied factory function that only requires no
  /// parameters to create an instance of `TSubject` with the provided
  /// [Configuration] instance.
  Func<String, Future<TSubject>> get boundFactoryAsync {
    return (sessionId) => this.factoryAsync(this.configuration, sessionId);
  }
}

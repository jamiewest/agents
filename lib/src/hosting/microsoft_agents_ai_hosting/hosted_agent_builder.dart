import 'package:extensions/dependency_injection.dart';
/// Represents a builder for configuring AI agents within a hosting
/// environment.
abstract class HostedAgentBuilder {
  /// Gets the name of the agent being configured.
  String get name;

  /// Gets the service collection for configuration.
  ServiceCollection get serviceCollection;

  /// Gets the DI service lifetime used for the agent registration.
  ServiceLifetime get lifetime;
}

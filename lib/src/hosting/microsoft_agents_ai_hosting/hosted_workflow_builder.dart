import 'package:extensions/hosting.dart';
/// Represents a builder for configuring workflows within a hosting
/// environment.
abstract class HostedWorkflowBuilder {
  /// Gets the name of the workflow being configured.
  String get name;

  /// Gets the application host builder for configuring additional services.
  HostApplicationBuilder get hostApplicationBuilder;
}

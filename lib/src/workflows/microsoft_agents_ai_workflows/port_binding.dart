import 'identified.dart';

/// Base class for bindings associated with named ports.
class PortBinding implements Identified {
  /// Creates a port binding.
  const PortBinding(this.id);

  /// Gets the port identifier.
  @override
  final String id;
}

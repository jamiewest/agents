/// The A2A host server: exposes local configured agents to paired devices
/// over HTTP.
///
/// The real server (`shelf` + `dart:io`) exists only where `dart:io` does;
/// on the web the stub reports hosting as unsupported. Import this facade,
/// never the halves.
library;

export 'a2a_host_service_stub.dart'
    if (dart.library.io) 'a2a_host_service_io.dart';

import 'package:extensions/dependency_injection.dart';

import 'download_service.dart';

/// Registers the background download service.
extension DownloadServiceCollectionExtensions on ServiceCollection {
  /// Registers a [DownloadService] singleton, disposed with the service
  /// provider.
  ///
  /// A [DownloadService] registered before this method is preserved. The
  /// service forwards plugin updates from construction; call
  /// [DownloadService.start] once at startup to resume downloads interrupted by
  /// an app restart.
  ServiceCollection addDownloadService() {
    tryAddSingleton<DownloadService>((_) => DownloadService());
    return this;
  }
}

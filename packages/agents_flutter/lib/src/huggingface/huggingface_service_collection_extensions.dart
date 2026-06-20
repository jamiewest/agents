import 'package:extensions/dependency_injection.dart';

import '../download/download_service.dart';
import '../download/download_service_collection_extensions.dart';
import 'huggingface_downloader.dart';

/// Registers the HuggingFace downloader.
extension HuggingFaceDownloaderServiceCollectionExtensions
    on ServiceCollection {
  /// Registers a [HuggingFaceDownloader] singleton, ensuring a
  /// [DownloadService] is registered for it to compose.
  ///
  /// [token] authorizes gated or private repositories. A [DownloadService] or
  /// [HuggingFaceDownloader] registered before this method is preserved.
  ServiceCollection addHuggingFaceDownloader({String? token}) {
    addDownloadService();
    tryAddSingleton<HuggingFaceDownloader>(
      (services) => HuggingFaceDownloader(
        services.getRequiredService<DownloadService>(),
        token: token,
      ),
    );
    return this;
  }
}

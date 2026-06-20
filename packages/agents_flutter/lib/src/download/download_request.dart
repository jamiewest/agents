/// A request to download a single file.
///
/// A plain, plugin-agnostic description of what to fetch and where to put it,
/// so callers (and [HuggingFaceDownloader]) never touch `background_downloader`
/// types directly. Defaults are tuned for large files: pausing and retries are
/// enabled so a multi-gigabyte model survives an interrupted connection.
final class DownloadRequest {
  /// Creates a download request for [url], saved as [filename].
  const DownloadRequest({
    required this.url,
    required this.filename,
    this.directory,
    this.headers,
    this.requiresWiFi = false,
    this.retries = 3,
    this.allowPause = true,
    this.metaData,
  });

  /// The absolute URL to download from.
  final String url;

  /// The name the downloaded file is saved as.
  final String filename;

  /// An optional subdirectory, relative to the app-managed storage root, to
  /// save the file in.
  final String? directory;

  /// Optional HTTP headers, such as an `Authorization` header for a gated
  /// resource.
  final Map<String, String>? headers;

  /// Whether the download should only run over Wi-Fi.
  final bool requiresWiFi;

  /// How many times to retry the download before failing.
  final int retries;

  /// Whether the download may be paused and resumed.
  ///
  /// Enabled by default so large downloads can resume after an interruption.
  final bool allowPause;

  /// Optional caller-defined metadata carried with the download.
  final String? metaData;
}

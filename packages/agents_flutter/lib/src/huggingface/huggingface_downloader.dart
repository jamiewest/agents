import '../download/download_request.dart';
import '../download/download_service.dart';
import '../download/download_update.dart';
import 'huggingface_api.dart';

/// Downloads model files from the HuggingFace Hub in the background.
///
/// Composes a [DownloadService] for the actual transfer and a [HuggingFaceApi]
/// for repository discovery, so it only builds resolve URLs and auth headers.
/// Model files are large, so [enqueueModel] (background, resumable) is usually
/// preferable to the awaited [downloadModel].
final class HuggingFaceDownloader {
  /// Creates a downloader backed by [downloads].
  ///
  /// [token] authorizes gated or private repositories; it is sent both to the
  /// Hub API and as a download `Authorization` header. [api] defaults to a
  /// [HuggingFaceApi] sharing [token] and [host], and [host] defaults to the
  /// public hub.
  HuggingFaceDownloader(
    this._downloads, {
    this.token,
    HuggingFaceApi? api,
    this.host = 'huggingface.co',
  }) : _api = api ?? HuggingFaceApi(token: token, host: host);

  final DownloadService _downloads;
  final HuggingFaceApi _api;

  /// An optional HuggingFace access token for gated or private repositories.
  final String? token;

  /// The hub host, e.g. `huggingface.co`.
  final String host;

  /// Builds the resolve URL for [filename] in [repoId] at [revision].
  ///
  /// For example, `resolveUri('TheBloke/Llama-2-7B-GGUF',
  /// 'llama-2-7b.Q4_K_M.gguf')` →
  /// `https://huggingface.co/TheBloke/Llama-2-7B-GGUF/resolve/main/llama-2-7b.Q4_K_M.gguf`.
  Uri resolveUri(String repoId, String filename, {String revision = 'main'}) =>
      Uri.https(host, '/$repoId/resolve/$revision/$filename');

  /// Enqueues a background download of [filename] from [repoId] and returns its
  /// task id, or null if it could not be enqueued.
  ///
  /// Progress and completion arrive through [DownloadService.updates]. The file
  /// is saved as its base name under [directory] (defaulting to a per-repo
  /// folder) in app-managed storage.
  Future<String?> enqueueModel({
    required String repoId,
    required String filename,
    String revision = 'main',
    String? directory,
  }) => _downloads.enqueue(_request(repoId, filename, revision, directory));

  /// Downloads [filename] from [repoId] and completes with its final status.
  ///
  /// Prefer [enqueueModel] for large files that should continue when the app is
  /// not in the foreground.
  Future<DownloadStatus> downloadModel({
    required String repoId,
    required String filename,
    String revision = 'main',
    String? directory,
    void Function(double progress)? onProgress,
  }) => _downloads.download(
    _request(repoId, filename, revision, directory),
    onProgress: onProgress,
  );

  /// Lists the files available in [repoId] at [revision].
  Future<HuggingFaceRepoInfo> listFiles(
    String repoId, {
    String revision = 'main',
  }) => _api.listFiles(repoId, revision: revision);

  DownloadRequest _request(
    String repoId,
    String filename,
    String revision,
    String? directory,
  ) => DownloadRequest(
    url: resolveUri(repoId, filename, revision: revision).toString(),
    filename: filename.split('/').last,
    directory: directory ?? repoId,
    headers: token == null ? null : {'Authorization': 'Bearer $token'},
    metaData: repoId,
  );
}

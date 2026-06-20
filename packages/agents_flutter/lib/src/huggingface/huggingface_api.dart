import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fetches the body of a GET request, or throws on a transport error.
///
/// Wrapping the HTTP call in a function type keeps `package:http` out of
/// [HuggingFaceApi]'s logic, so tests can inject canned JSON instead of hitting
/// the network. The implementation must throw on a non-success status so the
/// API surfaces a clear error.
typedef HttpGet =
    Future<String> Function(Uri url, {Map<String, String>? headers});

/// The default [HttpGet], backed by `package:http`.
Future<String> httpGetString(Uri url, {Map<String, String>? headers}) async {
  final response = await http.get(url, headers: headers);
  if (response.statusCode != 200) {
    throw HuggingFaceApiException(
      'GET $url failed with status ${response.statusCode}.',
    );
  }
  return response.body;
}

/// Thrown when the HuggingFace Hub API returns an error or malformed response.
final class HuggingFaceApiException implements Exception {
  /// Creates an exception with a human-readable [message].
  const HuggingFaceApiException(this.message);

  /// A description of what went wrong.
  final String message;

  @override
  String toString() => 'HuggingFaceApiException: $message';
}

/// A single file within a HuggingFace repository.
final class HuggingFaceFile {
  /// Creates a file reference for [path].
  const HuggingFaceFile(this.path);

  /// The file's path relative to the repository root, e.g. `config.json` or
  /// `onnx/decoder_model.onnx`.
  final String path;
}

/// Metadata about a HuggingFace repository revision and its files.
final class HuggingFaceRepoInfo {
  /// Creates repository info.
  const HuggingFaceRepoInfo({
    required this.sha,
    required this.gated,
    required this.private,
    required this.files,
  });

  /// The commit hash of the resolved revision, if reported.
  final String? sha;

  /// Whether the repository is gated and requires accepting terms (and a token)
  /// to download.
  final bool gated;

  /// Whether the repository is private.
  final bool private;

  /// The files available in the repository.
  final List<HuggingFaceFile> files;
}

/// Reads repository metadata from the HuggingFace Hub API.
final class HuggingFaceApi {
  /// Creates an API client.
  ///
  /// [token] authorizes access to gated or private repositories. [httpGet]
  /// defaults to [httpGetString] and can be overridden with a fake in tests.
  /// [host] defaults to the public hub.
  HuggingFaceApi({this.token, HttpGet? httpGet, this.host = 'huggingface.co'})
    : _httpGet = httpGet ?? httpGetString;

  /// An optional HuggingFace access token for gated or private repositories.
  final String? token;

  /// The hub host, e.g. `huggingface.co`.
  final String host;

  final HttpGet _httpGet;

  /// Fetches metadata and the file list for [repoId] at [revision].
  ///
  /// Throws a [HuggingFaceApiException] if the request fails or the response
  /// cannot be parsed.
  Future<HuggingFaceRepoInfo> listFiles(
    String repoId, {
    String revision = 'main',
  }) async {
    final url = revision == 'main'
        ? Uri.https(host, '/api/models/$repoId')
        : Uri.https(host, '/api/models/$repoId/revision/$revision');

    final body = await _httpGet(url, headers: _authHeaders());

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (error) {
      throw HuggingFaceApiException('Invalid response for $repoId: $error');
    }
    if (decoded is! Map<String, Object?>) {
      throw HuggingFaceApiException('Unexpected response for $repoId.');
    }

    final siblings = decoded['siblings'];
    final files = <HuggingFaceFile>[];
    if (siblings is List) {
      for (final sibling in siblings) {
        if (sibling is Map && sibling['rfilename'] is String) {
          files.add(HuggingFaceFile(sibling['rfilename'] as String));
        }
      }
    }

    // `gated` is reported as `false` or a string ("auto"/"manual"), so any
    // non-false, non-null value means the repo is gated.
    final gated = decoded['gated'];

    return HuggingFaceRepoInfo(
      sha: decoded['sha'] as String?,
      gated: gated != null && gated != false,
      private: decoded['private'] == true,
      files: files,
    );
  }

  /// The authorization headers for an authenticated request, or null when no
  /// token is set.
  Map<String, String>? _authHeaders() =>
      token == null ? null : {'Authorization': 'Bearer $token'};
}

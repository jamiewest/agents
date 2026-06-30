import 'package:http/http.dart' as http;

import 'gemini_defaults.dart';

/// Minimal REST client for the Gemini API.
final class GeminiClient {
  /// Creates a Gemini REST client.
  GeminiClient({
    required this.apiKey,
    http.Client? httpClient,
    Uri? baseUrl,
    Map<String, String>? defaultHeaders,
  }) : httpClient = httpClient ?? http.Client(),
       baseUrl = baseUrl ?? GeminiDefaults.defaultBaseUrl,
       defaultHeaders = Map.unmodifiable(defaultHeaders ?? const {}),
       _ownsHttpClient = httpClient == null;

  /// The API key sent as `x-goog-api-key`.
  final String apiKey;

  /// Base URL for Gemini API requests.
  final Uri baseUrl;

  /// Underlying HTTP client.
  final http.Client httpClient;

  /// Additional headers sent with each request.
  final Map<String, String> defaultHeaders;

  final bool _ownsHttpClient;

  /// Builds a model method endpoint.
  Uri endpoint(
    String modelId,
    String method, {
    Map<String, String>? queryParameters,
  }) {
    final modelPath = modelId.startsWith('models/')
        ? modelId
        : 'models/$modelId';
    final basePath = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    final query = <String, String>{
      ...baseUrl.queryParameters,
      ...?queryParameters,
    };

    return baseUrl.replace(
      path: '$basePath/$modelPath:$method',
      queryParameters: query.isEmpty ? null : query,
    );
  }

  /// Closes the underlying HTTP client if this instance created it.
  void close() {
    if (_ownsHttpClient) {
      httpClient.close();
    }
  }
}

// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;
import 'package:agents/agents.dart';
import 'package:extensions/ai.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'configured_agent_exception.dart';
import 'models/model_config.dart';
import 'models/model_source_config.dart';
import 'models/provider_type.dart';

/// Header that opts a browser build into direct Anthropic API access.
///
/// Required for Flutter web demos that call Anthropic from the client; it must
/// be threaded through whenever a client is rebuilt from stored config, or
/// browser requests are rejected.
const Map<String, String> anthropicWebHeaders = <String, String>{
  'anthropic-dangerous-direct-browser-access': 'true',
};

/// Builds a [ChatClient] from a stored source + model + API key.
///
/// Pure and stateless: it performs no persistence and reads no secrets itself.
/// Resolution of those values from storage is the job of
/// `ConfiguredAgentFactory`.
class ConfiguredChatClientFactory {
  /// Creates a [ConfiguredChatClientFactory].
  ///
  /// [isWeb] controls whether the Anthropic direct-browser-access header is
  /// attached; it defaults to [kIsWeb] in production and is overridable so the
  /// web code path can be exercised in tests, where [kIsWeb] is always false.
  const ConfiguredChatClientFactory({this.isWeb = kIsWeb});

  /// Whether to attach browser-access headers for Anthropic. See the
  /// constructor.
  final bool isWeb;

  /// Builds a chat client for [model] hosted by [source], authenticating with
  /// [apiKey].
  ///
  /// Supply [httpClient] to inject a fake transport in tests.
  ChatClient createChatClient({
    required ModelSourceConfig source,
    required ModelConfig model,
    required String apiKey,
    http.Client? httpClient,
  }) {
    final endpoint = source.endpoint;
    final hasEndpoint = endpoint != null && endpoint.isNotEmpty;

    _validateApiKey(apiKey);

    switch (source.providerType) {
      case ProviderType.openAiCompatible:
        return OpenAIChatClient(
          model.modelId,
          apiKey,
          options: OpenAIClientOptions(
            endpoint: hasEndpoint ? Uri.parse(endpoint) : null,
            httpClient: httpClient,
          ),
        );
      case ProviderType.anthropic:
        final client = anthropic.AnthropicClient.withApiKey(
          apiKey,
          baseUrl: hasEndpoint ? endpoint : null,
          defaultHeaders: isWeb ? anthropicWebHeaders : null,
          httpClient: httpClient,
        );
        return client.asChatClient(modelId: model.modelId);
    }
  }

  /// Rejects an [apiKey] that cannot be sent as an HTTP header value.
  ///
  /// The key is transmitted in a request header (`x-api-key` for Anthropic,
  /// `Authorization: Bearer` for OpenAI). On web, the browser `fetch` API only
  /// permits header values in the ISO-8859-1 (Latin-1) range, so a key carrying
  /// a code point above `0xFF` — a smart quote, em dash, zero-width space, or
  /// emoji picked up when pasting from rich text — fails with an opaque
  /// `fetch` error. Real provider keys are ASCII, so any such character is a
  /// paste artifact; surface a clear message instead.
  void _validateApiKey(String apiKey) {
    final runes = apiKey.runes.toList();
    for (var i = 0; i < runes.length; i++) {
      final rune = runes[i];
      if (rune > 0xFF) {
        throw ConfiguredAgentException(
          'API key contains an invalid character (U+'
          '${rune.toRadixString(16).toUpperCase().padLeft(4, '0')} at '
          'position ${i + 1}). Re-enter the key, taking care not to paste '
          'smart quotes or other formatting characters.',
        );
      }
    }
  }
}

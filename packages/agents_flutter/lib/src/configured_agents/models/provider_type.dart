// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The kind of provider a configured source talks to.
enum ProviderType {
  /// Any OpenAI-compatible Chat Completions endpoint.
  ///
  /// Covers the OpenAI API itself plus compatible providers (Groq, local
  /// inference servers, proxies) reachable by overriding the endpoint.
  openAiCompatible('openai_compatible'),

  /// Anthropic's Messages API.
  anthropic('anthropic'),

  /// Local GGUF inference provided by an embedding application.
  localLlama('local_llama');

  const ProviderType(this.wireName);

  /// The stable identifier persisted in configuration JSON.
  final String wireName;

  /// Whether sources of this type require a stored API key.
  bool get requiresApiKey => switch (this) {
    ProviderType.openAiCompatible || ProviderType.anthropic => true,
    ProviderType.localLlama => false,
  };

  /// Parses a [wireName] back into a [ProviderType].
  ///
  /// Throws an [ArgumentError] when [value] does not match a known provider.
  static ProviderType fromWireName(String value) => values.firstWhere(
    (type) => type.wireName == value,
    orElse: () => throw ArgumentError.value(value, 'value', 'Unknown provider'),
  );
}

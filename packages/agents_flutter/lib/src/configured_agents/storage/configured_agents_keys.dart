// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Centralized key schemes for configured-agents persistence.
///
/// Keeping every key in one place makes the secret/non-secret split explicit:
/// [sourceApiKeyKey] addresses a `SecretStore`, while the `*Prefix` values
/// address the non-secret `KeyValueStore`.
abstract final class ConfiguredAgentsKeys {
  /// `KeyValueStore` prefix for serialized [String] source configs.
  static const String sourcePrefix = 'agents_flutter.source.';

  /// `KeyValueStore` prefix for serialized model configs.
  static const String modelPrefix = 'agents_flutter.model.';

  /// `KeyValueStore` prefix for serialized saved-agent configs.
  static const String agentPrefix = 'agents_flutter.agent.';

  /// `SecretStore` key for the API key belonging to source [sourceId].
  static String sourceApiKeyKey(String sourceId) =>
      'agents_flutter.source_api_key.$sourceId';
}

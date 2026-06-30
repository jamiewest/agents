// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'provider_type.dart';

/// Configuration describing where models come from: a provider, an optional
/// endpoint, and any non-secret provider settings.
///
/// The matching API key is never stored here. It lives in a `SecretStore`,
/// keyed by [id] (see `ConfiguredAgentsSecrets.sourceApiKeyKey`).
class ModelSourceConfig {
  /// Creates a [ModelSourceConfig].
  const ModelSourceConfig({
    required this.id,
    required this.providerType,
    required this.displayName,
    this.endpoint,
    this.settings = const {},
  });

  /// Stable, app-unique identifier for this source.
  final String id;

  /// Which provider API this source speaks to.
  final ProviderType providerType;

  /// Human-readable name shown in the UI.
  final String displayName;

  /// Optional base URL override.
  ///
  /// For [ProviderType.openAiCompatible] this points at the
  /// `/v1`-style base of the target server. Ignored by Anthropic, which uses
  /// the SDK default endpoint.
  final String? endpoint;

  /// Non-secret provider settings (never API keys).
  final Map<String, String> settings;

  /// Returns a copy with the given fields replaced.
  ModelSourceConfig copyWith({
    String? id,
    ProviderType? providerType,
    String? displayName,
    String? endpoint,
    Map<String, String>? settings,
  }) => ModelSourceConfig(
    id: id ?? this.id,
    providerType: providerType ?? this.providerType,
    displayName: displayName ?? this.displayName,
    endpoint: endpoint ?? this.endpoint,
    settings: settings ?? this.settings,
  );

  /// Serializes this source to JSON. Contains no secret material.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'providerType': providerType.wireName,
    'displayName': displayName,
    if (endpoint != null) 'endpoint': endpoint,
    'settings': settings,
  };

  /// Reconstructs a [ModelSourceConfig] from [json].
  factory ModelSourceConfig.fromJson(
    Map<String, Object?> json,
  ) => ModelSourceConfig(
    id: json['id']! as String,
    providerType: ProviderType.fromWireName(json['providerType']! as String),
    displayName: json['displayName']! as String,
    endpoint: json['endpoint'] as String?,
    settings: <String, String>{
      for (final entry
          in (json['settings'] as Map<Object?, Object?>? ?? const {}).entries)
        entry.key! as String: entry.value! as String,
    },
  );
}

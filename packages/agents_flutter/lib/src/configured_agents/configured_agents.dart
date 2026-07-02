// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Runtime-configurable agents: persistent stores, secure secrets, and the
/// factories that resolve a saved agent into a runnable `AIAgent`.
library;

export 'agent_configuration_store.dart';
export 'agent_scope.dart';
export 'configured_agent_exception.dart';
export 'configured_agent_factory.dart';
export 'configured_agents_manager.dart';
export 'configured_agents_service_collection_extensions.dart';
export 'configured_chat_client_factory.dart';
export 'model_profile/model_profile.dart';
export 'model_source_store.dart';
export 'models/model_capabilities.dart';
export 'models/model_config.dart';
export 'models/model_source_config.dart';
export 'models/provider_type.dart';
export 'models/saved_agent_config.dart';
export 'storage/configured_agents_keys.dart';
export 'storage/flutter_secure_secret_store.dart';
export 'storage/in_memory_key_value_store.dart';
export 'storage/in_memory_secret_store.dart';
export 'storage/key_value_store.dart';
export 'storage/secret_store.dart';
export 'storage/shared_preferences_key_value_store.dart';

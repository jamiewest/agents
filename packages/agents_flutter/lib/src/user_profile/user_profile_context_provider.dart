// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents/agents.dart';
import 'package:extensions/system.dart';

import 'user_profile_settings.dart';

/// Puts the user's profile in front of every agent turn.
///
/// A context provider rather than a prefix on the agent's own instructions:
/// `ConfiguredAgentFactory` writes the saved agent's instructions onto the
/// chat options verbatim, so anything added there is overwritten. Context
/// providers are merged with those instructions at invocation time instead,
/// which also means an edit to the profile applies to the next turn without
/// rebuilding the agent.
class UserProfileContextProvider extends AIContextProvider {
  /// Creates a [UserProfileContextProvider] reading from [settings].
  UserProfileContextProvider(this._settings);

  final UserProfileSettings _settings;

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async => AIContext()..instructions = _settings.instructions;
}

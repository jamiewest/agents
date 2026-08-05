// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents/agents.dart';
import 'package:extensions/system.dart';

import 'skill_store.dart';

/// An [AgentSkillsSource] backed by a [SkillStore].
///
/// Reads the store on every request, so a skill created mid-conversation —
/// by the `create_skill` tool or the skills screen — is available on the
/// agent's very next turn. Do not wrap this source in
/// `CachingAgentSkillsSource`; its default refresh interval caches forever
/// and would defeat that immediacy.
class RecordStoreSkillsSource extends AgentSkillsSource {
  /// Creates a source reading from [store].
  RecordStoreSkillsSource(this._store);

  final SkillStore _store;

  @override
  Future<List<AgentSkill>> getSkills(
    AgentSkillsSourceContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final stored = await _store.list();
    // A hand-edited record can carry a name or description the frontmatter
    // rules reject. Skip it rather than letting one bad record fail every
    // turn of every conversation; the skills screen is where it gets fixed.
    return [
      for (final skill in stored)
        if (AgentSkillFrontmatter.validateName(skill.name).$1 &&
            AgentSkillFrontmatter.validateDescription(skill.description).$1)
          skill.toSkill(),
    ];
  }
}

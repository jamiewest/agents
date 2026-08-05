// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents/agents.dart';
import 'package:clock/clock.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'skill_store.dart';
import 'stored_skill.dart';

/// The name of the skill-creation tool.
const String createSkillToolName = 'create_skill';

/// Creates the skill-authoring tools over [store].
///
/// Currently a single `create_skill` tool: the model writes a named skill
/// into the store, and a `RecordStoreSkillsSource` over the same store makes
/// it loadable on the agent's next turn. Users edit or delete the result in
/// the skills screen.
///
/// A created skill injects instructions into future conversations, so the
/// tool requires per-call user approval by default. Pass
/// [requireApproval] `false` only when a host applies its own approval
/// policy.
List<AITool> createSkillAuthoringTools({
  required SkillStore store,
  bool requireApproval = true,
  Clock? clock,
}) {
  final effectiveClock = clock ?? const Clock();
  final function = AIFunctionFactory.create(
    name: createSkillToolName,
    description:
        'Creates a reusable skill: a named set of instructions saved for '
        'future conversations. The description tells future agents when the '
        'skill applies; the instructions are loaded only when the skill is '
        'used. The skill becomes available immediately.',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'name': {
          'type': 'string',
          'description':
              'Unique skill name: lowercase letters, numbers, and single '
              'hyphens, such as "commit-message-style". 64 characters max.',
        },
        'description': {
          'type': 'string',
          'description':
              'One or two sentences saying what the skill does and when to '
              'use it. Future agents choose skills by this text alone. '
              '1024 characters max.',
        },
        'instructions': {
          'type': 'string',
          'description':
              'The full instructions to follow when the skill is used. '
              'Markdown; include steps, constraints, and examples.',
        },
      },
      'required': ['name', 'description', 'instructions'],
      'additionalProperties': false,
    },
    returnSchema: const {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'status': {'type': 'string'},
      },
      'required': ['name', 'status'],
      'additionalProperties': false,
    },
    callback: (arguments, {CancellationToken? cancellationToken}) async {
      final name = arguments['name']?.toString().trim() ?? '';
      final description = arguments['description']?.toString().trim() ?? '';
      final instructions = arguments['instructions']?.toString().trim() ?? '';

      // Report invalid input to the model instead of throwing, like the
      // sibling tools.
      final (validName, nameReason) = AgentSkillFrontmatter.validateName(name);
      if (!validName) {
        return 'Error creating skill: $nameReason';
      }
      final (validDescription, descriptionReason) =
          AgentSkillFrontmatter.validateDescription(description);
      if (!validDescription) {
        return 'Error creating skill: $descriptionReason';
      }
      if (instructions.isEmpty) {
        return 'Error creating skill: instructions are required.';
      }
      if (await store.getByName(name) != null) {
        return 'Error creating skill: a skill named "$name" already exists. '
            'Choose a different name, or ask the user to edit the existing '
            'skill in the skills screen.';
      }

      final now = effectiveClock.now();
      await store.save(
        StoredSkill(
          id: store.newSkillId(),
          name: name,
          description: description,
          instructions: instructions,
          createdAt: now,
          updatedAt: now,
        ),
      );
      return {'name': name, 'status': 'created'};
    },
  );
  return [requireApproval ? ApprovalRequiredAIFunction(function) : function];
}

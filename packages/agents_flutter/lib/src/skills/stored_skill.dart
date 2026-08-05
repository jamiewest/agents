// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents/agents.dart';

/// A user- or agent-authored skill persisted in the app's record store.
///
/// Stored skills are the editable counterpart of the framework's
/// [AgentSkill]: plain name/description/instructions records that a skills
/// screen can list and edit, and that [AgentInlineSkill] turns back into a
/// loadable skill for the agent.
class StoredSkill {
  /// Creates a [StoredSkill].
  const StoredSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.instructions,
    required this.createdAt,
    required this.updatedAt,
  });

  /// The record id within the skills collection.
  final String id;

  /// The skill name shown to the model; must satisfy
  /// [AgentSkillFrontmatter.validateName].
  final String name;

  /// When to use the skill; must satisfy
  /// [AgentSkillFrontmatter.validateDescription].
  final String description;

  /// The instructions loaded when the model invokes the skill.
  final String instructions;

  /// When the skill was created.
  final DateTime createdAt;

  /// When the skill was last edited.
  final DateTime updatedAt;

  /// Returns a copy with the given fields replaced.
  StoredSkill copyWith({
    String? name,
    String? description,
    String? instructions,
    DateTime? updatedAt,
  }) => StoredSkill(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    instructions: instructions ?? this.instructions,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Serializes to the stored record value.
  Map<String, Object?> toRecord() => {
    'name': name,
    'description': description,
    'instructions': instructions,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Reconstructs a [StoredSkill] from a stored [record].
  factory StoredSkill.fromRecord(String id, Map<String, Object?> record) {
    DateTime parse(Object? value) =>
        DateTime.tryParse(value as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return StoredSkill(
      id: id,
      name: record['name'] as String? ?? '',
      description: record['description'] as String? ?? '',
      instructions: record['instructions'] as String? ?? '',
      createdAt: parse(record['createdAt']),
      updatedAt: parse(record['updatedAt']),
    );
  }

  /// Converts this record into a loadable [AgentSkill].
  ///
  /// Throws [ArgumentError] when [name] or [description] is invalid; callers
  /// listing arbitrary stored records should validate with
  /// [AgentSkillFrontmatter.validateName] and
  /// [AgentSkillFrontmatter.validateDescription] first.
  AgentSkill toSkill() =>
      AgentInlineSkill(instructions, name: name, description: description);
}

import 'package:agents/agents.dart';
import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 8, 1, 12);
  final updatedAt = DateTime.utc(2026, 8, 2, 8, 30);

  StoredSkill buildSkill() => StoredSkill(
    id: 'skill-1',
    name: 'commit-style',
    description: 'How to write commit messages for this project.',
    instructions: 'Use imperative mood. Keep the subject under 50 chars.',
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  test('round-trips through toRecord/fromRecord', () {
    final skill = buildSkill();

    final restored = StoredSkill.fromRecord('skill-1', skill.toRecord());

    expect(restored.id, skill.id);
    expect(restored.name, skill.name);
    expect(restored.description, skill.description);
    expect(restored.instructions, skill.instructions);
    expect(restored.createdAt, skill.createdAt);
    expect(restored.updatedAt, skill.updatedAt);
  });

  test('fromRecord tolerates missing fields', () {
    final restored = StoredSkill.fromRecord('skill-2', const {});

    expect(restored.name, isEmpty);
    expect(restored.description, isEmpty);
    expect(restored.instructions, isEmpty);
    expect(restored.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
  });

  test('copyWith replaces only the given fields', () {
    final skill = buildSkill();

    final edited = skill.copyWith(
      instructions: 'New instructions.',
      updatedAt: DateTime.utc(2026, 8, 3),
    );

    expect(edited.id, skill.id);
    expect(edited.name, skill.name);
    expect(edited.instructions, 'New instructions.');
    expect(edited.createdAt, createdAt);
    expect(edited.updatedAt, DateTime.utc(2026, 8, 3));
  });

  test('toSkill builds a loadable inline skill', () {
    final skill = buildSkill().toSkill();

    expect(skill, isA<AgentInlineSkill>());
    expect(skill.frontmatter.name, 'commit-style');
    expect(
      skill.frontmatter.description,
      'How to write commit messages for this project.',
    );
    expect(skill.content, contains('Use imperative mood.'));
  });

  test('toSkill throws on an invalid name', () {
    final skill = StoredSkill(
      id: 'skill-3',
      name: 'Not A Valid Name',
      description: 'Valid description.',
      instructions: 'Steps.',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    expect(skill.toSkill, throwsArgumentError);
  });
}

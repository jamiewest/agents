import 'package:agents/agents.dart';
import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// The source never touches the requesting agent, so any member access is a
/// test failure.
class _FakeAgent implements AIAgent {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late InMemoryRecordStore records;
  late SkillStore store;
  late RecordStoreSkillsSource source;
  late AgentSkillsSourceContext context;

  setUp(() {
    records = InMemoryRecordStore();
    store = SkillStore(records);
    source = RecordStoreSkillsSource(store);
    context = AgentSkillsSourceContext(_FakeAgent(), null);
  });

  StoredSkill buildSkill(String id, String name) => StoredSkill(
    id: id,
    name: name,
    description: 'Description for $name.',
    instructions: 'Instructions for $name.',
    createdAt: DateTime.utc(2026, 8, 1),
    updatedAt: DateTime.utc(2026, 8, 1),
  );

  test('returns stored skills as loadable skills', () async {
    await store.save(buildSkill('1', 'alpha'));
    await store.save(buildSkill('2', 'beta'));

    final skills = await source.getSkills(context);

    expect(skills.map((s) => s.frontmatter.name), ['alpha', 'beta']);
    expect(skills.first.content, contains('Instructions for alpha.'));
  });

  test('reflects a newly created skill on the next request', () async {
    expect(await source.getSkills(context), isEmpty);

    await store.save(buildSkill('1', 'alpha'));

    final skills = await source.getSkills(context);
    expect(skills, hasLength(1));
  });

  test('skips records with invalid frontmatter', () async {
    await store.save(buildSkill('1', 'alpha'));
    await records.put(SkillStore.collection, 'bad', {
      'name': 'Not Valid',
      'description': 'A hand-edited record with a bad name.',
      'instructions': 'Anything.',
    });
    await records.put(SkillStore.collection, 'blank', {
      'name': 'no-description',
      'description': '',
      'instructions': 'Anything.',
    });

    final skills = await source.getSkills(context);

    expect(skills.map((s) => s.frontmatter.name), ['alpha']);
  });
}

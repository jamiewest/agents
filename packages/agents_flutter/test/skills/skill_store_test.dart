import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SkillStore store;

  setUp(() {
    store = SkillStore(InMemoryRecordStore());
  });

  StoredSkill buildSkill(String id, String name) => StoredSkill(
    id: id,
    name: name,
    description: 'Description for $name.',
    instructions: 'Instructions for $name.',
    createdAt: DateTime.utc(2026, 8, 1),
    updatedAt: DateTime.utc(2026, 8, 1),
  );

  test('saves and loads a skill by id', () async {
    await store.save(buildSkill('a', 'alpha'));

    final loaded = await store.get('a');

    expect(loaded, isNotNull);
    expect(loaded!.name, 'alpha');
  });

  test('get returns null for a missing id', () async {
    expect(await store.get('missing'), isNull);
  });

  test('loads a skill by name', () async {
    await store.save(buildSkill('a', 'alpha'));
    await store.save(buildSkill('b', 'beta'));

    final loaded = await store.getByName('beta');

    expect(loaded, isNotNull);
    expect(loaded!.id, 'b');
    expect(await store.getByName('gamma'), isNull);
  });

  test('newSkillId generates unique ids', () {
    final ids = {for (var i = 0; i < 100; i++) store.newSkillId()};
    expect(ids, hasLength(100));
  });

  test('delete removes the skill', () async {
    await store.save(buildSkill('a', 'alpha'));

    await store.delete('a');

    expect(await store.get('a'), isNull);
  });

  test('list returns skills ordered by name', () async {
    await store.save(buildSkill('1', 'zeta'));
    await store.save(buildSkill('2', 'alpha'));
    await store.save(buildSkill('3', 'mid'));

    final skills = await store.list();

    expect(skills.map((s) => s.name), ['alpha', 'mid', 'zeta']);
  });

  test('watchAll emits current skills and updates on change', () async {
    await store.save(buildSkill('1', 'alpha'));

    final emissions = <List<StoredSkill>>[];
    final subscription = store.watchAll().listen(emissions.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(emissions.last.map((s) => s.name), ['alpha']);

    await store.save(buildSkill('2', 'beta'));
    await pumpEventQueue();

    expect(emissions.last.map((s) => s.name), ['alpha', 'beta']);
  });
}

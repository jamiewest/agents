import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixedClock = Clock.fixed(DateTime.utc(2026, 8, 4, 10));
  late SkillStore store;

  setUp(() {
    store = SkillStore(InMemoryRecordStore());
  });

  AIFunction buildTool({bool requireApproval = false}) =>
      createSkillAuthoringTools(
            store: store,
            requireApproval: requireApproval,
            clock: fixedClock,
          ).single
          as AIFunction;

  test('requires approval by default', () {
    final tools = createSkillAuthoringTools(store: store);

    expect(tools.single, isA<ApprovalRequiredAIFunction>());
    expect((tools.single as AIFunction).name, createSkillToolName);
  });

  test('skips the approval wrapper when disabled', () {
    expect(buildTool(), isNot(isA<ApprovalRequiredAIFunction>()));
  });

  test('creates a skill that is immediately in the store', () async {
    final result = await buildTool().invoke(
      AIFunctionArguments({
        'name': 'commit-style',
        'description': 'How to write commit messages.',
        'instructions': 'Use imperative mood.',
      }),
    );

    expect(result, {'name': 'commit-style', 'status': 'created'});
    final saved = await store.getByName('commit-style');
    expect(saved, isNotNull);
    expect(saved!.description, 'How to write commit messages.');
    expect(saved.instructions, 'Use imperative mood.');
    expect(saved.createdAt, fixedClock.now());
    expect(saved.updatedAt, fixedClock.now());
  });

  test('rejects an invalid name without saving', () async {
    final result = await buildTool().invoke(
      AIFunctionArguments({
        'name': 'Not A Valid Name',
        'description': 'Valid description.',
        'instructions': 'Steps.',
      }),
    );

    expect(result, isA<String>());
    expect(result as String, contains('Error creating skill'));
    expect(await store.list(), isEmpty);
  });

  test('rejects a missing description without saving', () async {
    final result = await buildTool().invoke(
      AIFunctionArguments({
        'name': 'valid-name',
        'description': '   ',
        'instructions': 'Steps.',
      }),
    );

    expect(result, isA<String>());
    expect(result as String, contains('description'));
    expect(await store.list(), isEmpty);
  });

  test('rejects missing instructions without saving', () async {
    final result = await buildTool().invoke(
      AIFunctionArguments({
        'name': 'valid-name',
        'description': 'Valid description.',
        'instructions': '',
      }),
    );

    expect(result, isA<String>());
    expect(result as String, contains('instructions'));
    expect(await store.list(), isEmpty);
  });

  test('rejects a duplicate name', () async {
    final tool = buildTool();
    final arguments = {
      'name': 'commit-style',
      'description': 'How to write commit messages.',
      'instructions': 'Use imperative mood.',
    };
    await tool.invoke(AIFunctionArguments(arguments));

    final result = await tool.invoke(AIFunctionArguments(arguments));

    expect(result, isA<String>());
    expect(result as String, contains('already exists'));
    expect(await store.list(), hasLength(1));
  });
}

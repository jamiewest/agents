import 'package:agents/src/workflows/microsoft_agents_ai_workflows/workflow.dart';
import 'package:test/test.dart';

void main() {
  group('Workflow', () {
    test('stores start id, name, and description', () {
      final workflow = Workflow(
        'start',
        name: 'workflow-name',
        description: 'Workflow description.',
      );

      expect(workflow.startExecutorId, 'start');
      expect(workflow.name, 'workflow-name');
      expect(workflow.description, 'Workflow description.');
      expect(workflow.allowConcurrent, isTrue);
      expect(workflow.nonConcurrentExecutorIds, isEmpty);
      expect(workflow.hasResettableExecutors, isFalse);
    });

    test('ownership can be taken checked and released', () async {
      final workflow = Workflow('start');
      final owner = Object();

      workflow.takeOwnership(owner);
      workflow.checkOwnership(existingOwnershipSignoff: owner);
      await workflow.releaseOwnership(owner, null);

      workflow.checkOwnership();
    });

    test('ownership rejects mismatched owners', () async {
      final workflow = Workflow('start');
      final owner = Object();
      final other = Object();

      workflow.takeOwnership(owner);

      expect(
        () => workflow.checkOwnership(existingOwnershipSignoff: other),
        throwsStateError,
      );
      expect(() => workflow.takeOwnership(other), throwsStateError);
      expect(() => workflow.releaseOwnership(other, null), throwsStateError);
    });

    test('subworkflow ownership reports matching error', () {
      final workflow = Workflow('start');
      final owner = Object();

      workflow.takeOwnership(owner, subworkflow: true);

      expect(
        () => workflow.takeOwnership(Object(), subworkflow: true),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('subworkflow of multiple parent workflows'),
          ),
        ),
      );
    });
  });
}

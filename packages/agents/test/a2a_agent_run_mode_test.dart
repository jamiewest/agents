import 'package:a2a/a2a.dart';
import 'package:agents/src/hosting/a2a/a2a_run_decision_context.dart';
import 'package:agents/src/hosting/a2a/agent_run_mode.dart';
import 'package:test/test.dart';

A2ARunDecisionContext _decisionContext() {
  final message = A2AMessage()..role = 'user';
  final request = A2ARequestContext(message, null, null, 'task-1', 'ctx-1');
  return A2ARunDecisionContext(request);
}

void main() {
  group('AgentRunMode', () {
    test('returnMessage never returns a task', () async {
      final result = await AgentRunMode.returnMessage.shouldReturnTask(
        _decisionContext(),
      );

      expect(result, isFalse);
    });

    test('returnTask always returns a task', () async {
      final result = await AgentRunMode.returnTask.shouldReturnTask(
        _decisionContext(),
      );

      expect(result, isTrue);
    });

    test('returnTaskWhen invokes the supplied delegate', () async {
      var called = false;
      final mode = AgentRunMode.returnTaskWhen((context, _) async {
        called = true;
        return true;
      });

      final result = await mode.shouldReturnTask(_decisionContext());

      expect(called, isTrue);
      expect(result, isTrue);
    });

    test('returnTaskWhen passes the decision context through', () async {
      final context = _decisionContext();
      A2ARunDecisionContext? received;
      final mode = AgentRunMode.returnTaskWhen((c, _) async {
        received = c;
        return false;
      });

      await mode.shouldReturnTask(context);

      expect(received, same(context));
    });

    test('built-in modes compare equal to themselves', () {
      expect(AgentRunMode.returnMessage == AgentRunMode.returnMessage, isTrue);
      expect(AgentRunMode.returnMessage == AgentRunMode.returnTask, isFalse);
    });

    test('dynamic modes with different delegates are not equal', () {
      final a = AgentRunMode.returnTaskWhen((_, _) async => true);
      final b = AgentRunMode.returnTaskWhen((_, _) async => true);

      expect(a == b, isFalse);
      expect(a == a, isTrue);
    });

    test('toString reflects the mode discriminator', () {
      expect(AgentRunMode.returnMessage.toString(), 'message');
      expect(AgentRunMode.returnTask.toString(), 'task');
      expect(
        AgentRunMode.returnTaskWhen((_, _) async => true).toString(),
        'dynamic',
      );
    });

    test('equal built-in modes share a hash code', () {
      expect(
        AgentRunMode.returnMessage.hashCode,
        AgentRunMode.returnMessage.hashCode,
      );
    });
  });
}

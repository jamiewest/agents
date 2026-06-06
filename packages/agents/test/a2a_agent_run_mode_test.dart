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
    test('disallowBackground never runs in background', () async {
      final result = await AgentRunMode.disallowBackground
          .shouldRunInBackground(_decisionContext());

      expect(result, isFalse);
    });

    test('allowBackgroundIfSupported always runs in background', () async {
      final result = await AgentRunMode.allowBackgroundIfSupported
          .shouldRunInBackground(_decisionContext());

      expect(result, isTrue);
    });

    test('allowBackgroundWhen invokes the supplied delegate', () async {
      var called = false;
      final mode = AgentRunMode.allowBackgroundWhen((context, _) async {
        called = true;
        return true;
      });

      final result = await mode.shouldRunInBackground(_decisionContext());

      expect(called, isTrue);
      expect(result, isTrue);
    });

    test('allowBackgroundWhen passes the decision context through', () async {
      final context = _decisionContext();
      A2ARunDecisionContext? received;
      final mode = AgentRunMode.allowBackgroundWhen((c, _) async {
        received = c;
        return false;
      });

      await mode.shouldRunInBackground(context);

      expect(received, same(context));
    });

    test('built-in modes compare equal to themselves', () {
      expect(
        AgentRunMode.disallowBackground == AgentRunMode.disallowBackground,
        isTrue,
      );
      expect(
        AgentRunMode.disallowBackground ==
            AgentRunMode.allowBackgroundIfSupported,
        isFalse,
      );
    });

    test('dynamic modes with different delegates are not equal', () {
      final a = AgentRunMode.allowBackgroundWhen((_, _) async => true);
      final b = AgentRunMode.allowBackgroundWhen((_, _) async => true);

      expect(a == b, isFalse);
      expect(a == a, isTrue);
    });

    test('toString reflects the mode discriminator', () {
      expect(AgentRunMode.disallowBackground.toString(), 'message');
      expect(AgentRunMode.allowBackgroundIfSupported.toString(), 'task');
      expect(
        AgentRunMode.allowBackgroundWhen((_, _) async => true).toString(),
        'dynamic',
      );
    });

    test('equal built-in modes share a hash code', () {
      expect(
        AgentRunMode.disallowBackground.hashCode,
        AgentRunMode.disallowBackground.hashCode,
      );
    });
  });
}

import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:test/test.dart';

void main() {
  group('AgentSession', () {
    test('stateBag_Values_Roundtrips', () {
      final session = _TestSession();

      session.stateBag.setValue<String>('key', 'value');
      final result = session.stateBag.getValue<String>('key');

      expect(result, 'value');
    });

    test('getService_RequestingExactSessionType_ReturnsSession', () {
      final session = _TestSession();

      final service = session.getService(_TestSession);

      expect(service, same(session));
    });

    test('getService_RequestingUnrelatedType_ReturnsNull', () {
      final session = _TestSession();

      final service = session.getService(String);

      expect(service, isNull);
    });

    test('getService_WithServiceKey_ReturnsNull', () {
      final session = _TestSession();

      final service = session.getService(_TestSession, serviceKey: 'key');

      expect(service, isNull);
    });
  });

  group('AgentSessionStateBag', () {
    test('stateBag_SerializeDeserialize_RoundtripsValues', () {
      final bag = AgentSessionStateBag(null);
      bag.setValue<String>('name', 'Alice');
      bag.setValue<int>('age', 30);

      final json = bag.serialize();
      final restored = AgentSessionStateBag.deserialize(json);

      expect(restored.getValue<String>('name'), 'Alice');
      expect(restored.getValue<int>('age'), 30);
    });

    test('stateBag_TryGetValue_ReturnsFalseForMissingKey', () {
      final bag = AgentSessionStateBag(null);

      final (found, value) = bag.tryGetValue<String>('missing');

      expect(found, isFalse);
      expect(value, isNull);
    });

    test('stateBag_TryRemoveValue_RemovesAndReturnsBool', () {
      final bag = AgentSessionStateBag(null);
      bag.setValue<String>('key', 'val');

      final removed = bag.tryRemoveValue('key');
      final removedAgain = bag.tryRemoveValue('key');

      expect(removed, isTrue);
      expect(removedAgain, isFalse);
      expect(bag.getValue<String>('key'), isNull);
    });

    test('stateBag_Count_ReflectsEntries', () {
      final bag = AgentSessionStateBag(null);

      expect(bag.count, 0);

      bag.setValue<String>('a', 'x');
      expect(bag.count, 1);

      bag.setValue<String>('b', 'y');
      expect(bag.count, 2);

      bag.tryRemoveValue('a');
      expect(bag.count, 1);
    });
  });
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}

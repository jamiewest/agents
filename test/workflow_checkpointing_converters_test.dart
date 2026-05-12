import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpoint_info.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/checkpoint_info_converter.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/delayed_deserialization.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/edge_id_converter.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/executor_identity_converter.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/json_converter_dictionary_support_base.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/json_wire_serialized_value.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/portable_value_converter.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/scope_key_converter.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/edge_id.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/execution/executor_identity.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/portable_value.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/scope_id.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/scope_key.dart';
import 'package:test/test.dart';

void main() {
  // ---------------------------------------------------------------------------
  group('JsonConverterDictionarySupportBase escape/unescape', () {
    test('escape non-null value without pad doubles pipes', () {
      expect(
        JsonConverterDictionarySupportBase.escape('a|b'),
        equals('a||b'),
      );
    });

    test('escape non-null value with allowNullAndPad prefixes @', () {
      expect(
        JsonConverterDictionarySupportBase.escape('a|b', allowNullAndPad: true),
        equals('@a||b'),
      );
    });

    test('escape null with allowNullAndPad returns empty string', () {
      expect(
        JsonConverterDictionarySupportBase.escape(
          null,
          allowNullAndPad: true,
        ),
        equals(''),
      );
    });

    test('escape null without allowNullAndPad throws', () {
      expect(
        () => JsonConverterDictionarySupportBase.escape(null),
        throwsA(isA<FormatException>()),
      );
    });

    test('unescape doubled pipes produces single pipe', () {
      expect(
        JsonConverterDictionarySupportBase.unescape('a||b'),
        equals('a|b'),
      );
    });

    test('unescape with allowNullAndPad strips @ prefix', () {
      expect(
        JsonConverterDictionarySupportBase.unescape(
          '@a||b',
          allowNullAndPad: true,
        ),
        equals('a|b'),
      );
    });

    test('unescape empty with allowNullAndPad returns null', () {
      expect(
        JsonConverterDictionarySupportBase.unescape(
          '',
          allowNullAndPad: true,
        ),
        isNull,
      );
    });

    test('unescape empty without allowNullAndPad throws', () {
      expect(
        () => JsonConverterDictionarySupportBase.unescape(''),
        throwsA(isA<FormatException>()),
      );
    });

    test('unescape missing @ prefix with allowNullAndPad throws', () {
      expect(
        () => JsonConverterDictionarySupportBase.unescape(
          'nope',
          allowNullAndPad: true,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('ScopeKeyConverter', () {
    final converter = ScopeKeyConverter();

    test('roundtrip unnamed scope', () {
      final key = ScopeKey(ScopeId('exec-1'), 'myKey');
      final str = converter.stringify(key);
      final parsed = converter.parse(str);
      expect(parsed.scopeId.executorId, equals('exec-1'));
      expect(parsed.scopeId.scopeName, isNull);
      expect(parsed.key, equals('myKey'));
    });

    test('roundtrip named scope', () {
      final key = ScopeKey(ScopeId('exec-1', 'shared'), 'myKey');
      final str = converter.stringify(key);
      final parsed = converter.parse(str);
      expect(parsed.scopeId.executorId, equals('exec-1'));
      expect(parsed.scopeId.scopeName, equals('shared'));
      expect(parsed.key, equals('myKey'));
    });

    test('roundtrip with pipe characters in components', () {
      final key = ScopeKey(ScopeId('exec|1', 'scope|name'), 'k|ey');
      final str = converter.stringify(key);
      final parsed = converter.parse(str);
      expect(parsed.scopeId.executorId, equals('exec|1'));
      expect(parsed.scopeId.scopeName, equals('scope|name'));
      expect(parsed.key, equals('k|ey'));
    });

    test('parse throws for invalid format', () {
      expect(
        () => converter.parse('nope'),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson with string delegates to parse', () {
      final key = ScopeKey(ScopeId('e', 'n'), 'k');
      final str = converter.stringify(key);
      final result = converter.fromJson(str);
      expect(result?.key, equals('k'));
    });

    test('fromJson with non-string returns null', () {
      expect(converter.fromJson(42), isNull);
    });

    test('toJson returns stringify result', () {
      final key = ScopeKey(ScopeId('e'), 'k');
      expect(converter.toJson(key), equals(converter.stringify(key)));
    });
  });

  // ---------------------------------------------------------------------------
  group('EdgeIdConverter', () {
    final converter = EdgeIdConverter();

    test('stringify returns value string', () {
      expect(converter.stringify(const EdgeId('e1')), equals('e1'));
    });

    test('parse creates EdgeId from string', () {
      expect(converter.parse('e2').value, equals('e2'));
    });

    test('roundtrip', () {
      const id = EdgeId('my-edge');
      expect(converter.parse(converter.stringify(id)), equals(id));
    });

    test('fromJson with string returns EdgeId', () {
      expect(converter.fromJson('edge-x')?.value, equals('edge-x'));
    });

    test('fromJson with non-string returns null', () {
      expect(converter.fromJson(1), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('ExecutorIdentityConverter', () {
    final converter = ExecutorIdentityConverter();

    test('stringify None is empty string', () {
      expect(converter.stringify(ExecutorIdentity.none), equals(''));
    });

    test('stringify non-None prefixes with @', () {
      expect(converter.stringify(ExecutorIdentity('abc')), equals('@abc'));
    });

    test('parse empty string is None', () {
      expect(converter.parse(''), equals(ExecutorIdentity.none));
    });

    test('parse @-prefixed string', () {
      expect(converter.parse('@abc').id, equals('abc'));
    });

    test('parse invalid key throws', () {
      expect(
        () => converter.parse('noAt'),
        throwsA(isA<FormatException>()),
      );
    });

    test('roundtrip None', () {
      expect(
        converter.parse(converter.stringify(ExecutorIdentity.none)),
        equals(ExecutorIdentity.none),
      );
    });

    test('roundtrip non-None', () {
      final id = ExecutorIdentity('worker-1');
      expect(converter.parse(converter.stringify(id)).id, equals('worker-1'));
    });
  });

  // ---------------------------------------------------------------------------
  group('CheckpointInfoConverter', () {
    final converter = CheckpointInfoConverter();

    test('stringify produces escaped checkpointId', () {
      final info = CheckpointInfo('cp|1');
      expect(converter.stringify(info), equals('cp||1'));
    });

    test('parse roundtrip', () {
      final info = CheckpointInfo('cp-abc');
      expect(converter.parse(converter.stringify(info)).checkpointId,
          equals('cp-abc'));
    });

    test('fromJson with Map delegates to CheckpointInfo.fromJson', () {
      final info = CheckpointInfo('x');
      final json = info.toJson();
      final result = converter.fromJson(json);
      expect(result?.checkpointId, equals('x'));
    });
  });

  // ---------------------------------------------------------------------------
  group('JsonWireSerializedValue IDelayedDeserialization', () {
    test('deserialize returns value when type matches', () {
      const wire = JsonWireSerializedValue(value: 'hello');
      expect(wire.deserialize<String>(), equals('hello'));
    });

    test('deserialize throws when type does not match', () {
      const wire = JsonWireSerializedValue(value: 42);
      expect(() => wire.deserialize<String>(), throwsA(isA<StateError>()));
    });

    test('deserializeAs returns value for exact type', () {
      const wire = JsonWireSerializedValue(value: 'world');
      expect(wire.deserializeAs(String), equals('world'));
    });

    test('deserializeAs returns null for wrong type', () {
      const wire = JsonWireSerializedValue(value: 'world');
      expect(wire.deserializeAs(int), isNull);
    });

    test('implements IDelayedDeserialization', () {
      const wire = JsonWireSerializedValue(value: 'x');
      expect(wire, isA<IDelayedDeserialization>());
    });
  });

  // ---------------------------------------------------------------------------
  group('PortableValue toJson/fromJson', () {
    test('toJson includes typeId and value', () {
      final pv = PortableValue('hello');
      final json = pv.toJson();
      expect(json['typeId'], isA<String>());
      expect(json['value'], equals('hello'));
    });

    test('fromJson roundtrip for string value', () {
      final original = PortableValue('world');
      final json = original.toJson();
      final restored = PortableValue.fromJson(json);
      expect(restored.asValue<String>(), equals('world'));
    });

    test('fromJson wraps value in JsonWireSerializedValue', () {
      final pv = PortableValue.fromJson({'typeId': 'String', 'value': 42});
      expect(pv.isDelayedDeserialization, isTrue);
    });

    test('isDelayedDeserialization is true for wire value', () {
      final pv = PortableValue.fromJson({'typeId': 'int', 'value': 99});
      expect(pv.isDelayedDeserialization, isTrue);
    });

    test('isDeserialized is false before asValue call', () {
      final pv = PortableValue.fromJson({'typeId': 'int', 'value': 99});
      expect(pv.isDeserialized, isFalse);
    });

    test('isDeserialized is true after successful asValue call', () {
      final pv = PortableValue.fromJson({'typeId': 'int', 'value': 99});
      pv.asValue<int>();
      expect(pv.isDeserialized, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('PortableValueConverter', () {
    final converter = PortableValueConverter();

    test('fromJson returns PortableValue', () {
      final pv = converter.fromJson({'typeId': 'String', 'value': 'x'});
      expect(pv, isNotNull);
      expect(pv!.asValue<String>(), equals('x'));
    });

    test('fromJson returns null for non-map', () {
      expect(converter.fromJson('bad'), isNull);
    });

    test('toJson produces map with typeId and value', () {
      final pv = PortableValue('abc');
      final json = converter.toJson(pv) as Map;
      expect(json['typeId'], isA<String>());
      expect(json['value'], equals('abc'));
    });
  });
}

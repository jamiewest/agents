import 'package:agents_flutter/src/wake_lock/wake_lock_tool.dart';
import 'package:extensions/ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('set_wake_lock', () {
    test('enables the screen wake lock', () async {
      bool? requestedState;
      final tool = createWakeLockTool(
        toggleWakeLock: ({required enable}) async {
          requestedState = enable;
        },
      );

      final result = await tool.invoke(AIFunctionArguments({'enabled': true}));

      expect(requestedState, isTrue);
      expect(result, 'Screen wake lock enabled.');
    });

    test('disables the screen wake lock', () async {
      bool? requestedState;
      final tool = createWakeLockTool(
        toggleWakeLock: ({required enable}) async {
          requestedState = enable;
        },
      );

      final result = await tool.invoke(AIFunctionArguments({'enabled': false}));

      expect(requestedState, isFalse);
      expect(result, 'Screen wake lock disabled.');
    });

    test('declares a required boolean enabled argument', () {
      final tool = createWakeLockTool(
        toggleWakeLock: ({required enable}) async {},
      );

      expect(tool.name, 'set_wake_lock');
      expect(tool.parametersSchema, {
        'type': 'object',
        'properties': {
          'enabled': {
            'type': 'boolean',
            'description':
                'True to keep the screen awake; false to restore normal '
                'automatic screen sleep.',
          },
        },
        'required': ['enabled'],
        'additionalProperties': false,
      });
    });

    test('rejects a missing or non-boolean enabled argument', () async {
      var toggleCalls = 0;
      final tool = createWakeLockTool(
        toggleWakeLock: ({required enable}) async {
          toggleCalls++;
        },
      );

      expect(
        await tool.invoke(AIFunctionArguments()),
        'The enabled argument must be a boolean.',
      );
      expect(
        await tool.invoke(AIFunctionArguments({'enabled': 'true'})),
        'The enabled argument must be a boolean.',
      );
      expect(toggleCalls, 0);
    });

    test('returns a useful error when the platform call fails', () async {
      final tool = createWakeLockTool(
        toggleWakeLock: ({required enable}) async {
          throw StateError('platform unavailable');
        },
      );

      final result = await tool.invoke(AIFunctionArguments({'enabled': true}));

      expect(result, contains('Error setting screen wake lock'));
      expect(result, contains('platform unavailable'));
    });
  });
}

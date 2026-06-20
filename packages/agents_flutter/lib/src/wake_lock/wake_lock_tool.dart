import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Sets whether the device screen should be kept awake.
typedef WakeLockToggle = Future<void> Function({required bool enable});

/// Creates a tool that enables or disables the device's screen wake lock.
///
/// This controls automatic screen sleep only. It does not keep the app or CPU
/// running in the background. [toggleWakeLock] can be overridden with a fake
/// in tests.
AIFunction createWakeLockTool({WakeLockToggle? toggleWakeLock}) {
  final toggle = toggleWakeLock ?? WakelockPlus.toggle;

  return AIFunctionFactory.create(
    name: 'set_wake_lock',
    description:
        'Enables or disables the device screen wake lock. Enable it when the '
        'user wants the screen to remain on, and disable it to restore normal '
        'automatic screen sleep. This does not keep the app running in the '
        'background.',
    parametersSchema: const {
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
    },
    callback: (arguments, {CancellationToken? cancellationToken}) async {
      final enabled = arguments['enabled'];
      if (enabled is! bool) {
        return 'The enabled argument must be a boolean.';
      }

      try {
        await toggle(enable: enabled);
        return enabled
            ? 'Screen wake lock enabled.'
            : 'Screen wake lock disabled.';
      } catch (error) {
        return 'Error setting screen wake lock: $error';
      }
    },
  );
}

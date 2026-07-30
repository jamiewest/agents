import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Subsystems folded in from the downstream app that must stay free of
/// Flutter UI imports (`package:flutter/material.dart`, `widgets.dart`,
/// `cupertino.dart`).
///
/// `package:flutter/foundation.dart` is allowed. Keeping these directories
/// UI-free is what makes a future mechanical split into a pure-Dart core
/// package (for a CLI frontend) possible — see the repo plan.
const _uiFreeDirs = [
  'lib/src/activity',
  'lib/src/chat_provider',
  'lib/src/conversations',
  'lib/src/tasks',
  'lib/src/telemetry',
];

final _forbidden = RegExp(
  "import 'package:flutter/(material|widgets|cupertino)\\.dart'",
);

void main() {
  test('folded-in subsystems import no Flutter UI libraries', () {
    final offenders = <String>[];
    for (final dirPath in _uiFreeDirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();
        if (_forbidden.hasMatch(content)) {
          offenders.add(entity.path);
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'These files import Flutter UI libraries from a UI-free '
          'subsystem; use foundation-level APIs (or move the UI half to '
          'the host app) instead.',
    );
  });
}

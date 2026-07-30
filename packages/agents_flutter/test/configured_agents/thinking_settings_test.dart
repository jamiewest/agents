import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThinkingSettings', () {
    test('persists per-model preferences and reloads them', () async {
      final kv = InMemoryKeyValueStore();
      final settings = ThinkingSettings(kv);

      expect(settings.enabledFor('m1'), isFalse);
      await settings.setEnabled('m1', true);
      expect(settings.enabledFor('m1'), isTrue);

      final reloaded = ThinkingSettings(kv);
      await reloaded.load();
      expect(reloaded.enabledFor('m1'), isTrue);

      await reloaded.setEnabled('m1', false);
      expect(reloaded.enabledFor('m1'), isFalse);
      // The literal key prefix predates the fold-in and must not change:
      // existing installs have data under it.
      expect(await kv.keys(prefix: 'agents_app.thinking.'), isEmpty);
    });
  });
}

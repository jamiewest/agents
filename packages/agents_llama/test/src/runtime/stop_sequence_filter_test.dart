import 'package:agents_llama/agents_llama.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StopSequenceFilter', () {
    test('passes through streams without stop sequences', () async {
      final values = await const StopSequenceFilter(
        <String>[],
      ).bind(Stream.fromIterable(<String>['he', 'llo'])).join();

      expect(values, 'hello');
    });

    test('strips a stop sequence within one chunk', () async {
      final values = await const StopSequenceFilter(<String>[
        '<stop>',
      ]).bind(Stream.fromIterable(<String>['hello<stop>ignored'])).join();

      expect(values, 'hello');
    });

    test('strips a stop sequence split across chunks', () async {
      final values = await const StopSequenceFilter(<String>[
        '<turn|>',
      ]).bind(Stream.fromIterable(<String>['hello <tu', 'rn|>ignored'])).join();

      expect(values, 'hello ');
    });

    test('uses the earliest matching stop sequence', () async {
      final values = await const StopSequenceFilter(<String>[
        'world',
        'there',
      ]).bind(Stream.fromIterable(<String>['hello there world'])).join();

      expect(values, 'hello ');
    });
  });
}

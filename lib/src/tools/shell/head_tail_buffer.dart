import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

/// Bounded accumulator that keeps the first half of the input and the most
/// recent half (rolling tail), summing to [cap] UTF-8 bytes total.
///
/// When the input fits in [cap] bytes the result is the original concatenation.
/// Otherwise the middle is dropped and the result includes a
/// `[... truncated N bytes ...]` marker.
///
/// Memory usage is bounded at roughly [cap] bytes regardless of how much is
/// appended. Runes are never split: the final string never contains an orphan
/// surrogate or invalid UTF-8 sequence.
class HeadTailBuffer {
  /// Creates a [HeadTailBuffer] with the given byte [cap].
  HeadTailBuffer(int cap) : _cap = cap < 0 ? 0 : cap {
    _headCap = _cap ~/ 2;
    _tailCap = _cap - _headCap;
  }

  final int _cap;
  late final int _headCap;
  late final int _tailCap;
  final List<int> _head = [];
  final Queue<Uint8List> _tail = Queue();
  int _tailBytes = 0;
  int _totalBytes = 0;

  /// Appends [line] followed by a newline character.
  void appendLine(String line) {
    _appendInternal(line);
    _appendInternal('\n');
  }

  void _appendInternal(String s) {
    for (final rune in s.runes) {
      final bytes = _encodeRune(rune);
      final n = bytes.length;
      _totalBytes += n;

      if (_head.length + n <= _headCap) {
        _head.addAll(bytes);
        continue;
      }

      // Head is full — append to tail as a single rune-sized chunk.
      final chunk = Uint8List.fromList(bytes);
      _tail.add(chunk);
      _tailBytes += n;

      // Evict whole runes from the front of the tail until we fit.
      while (_tailBytes > _tailCap && _tail.isNotEmpty) {
        _tailBytes -= _tail.removeFirst().length;
      }
    }
  }

  /// Returns the accumulated text and whether it was truncated.
  (String text, bool truncated) toFinalString() {
    if (_totalBytes <= _cap) {
      final combined = Uint8List(_head.length + _tailBytes);
      combined.setAll(0, _head);
      var offset = _head.length;
      for (final chunk in _tail) {
        combined.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      return (utf8.decode(combined), false);
    }

    final dropped = _totalBytes - _head.length - _tailBytes;
    final headStr = utf8.decode(_head);

    final tailRaw = Uint8List(_tailBytes);
    var tailOffset = 0;
    for (final chunk in _tail) {
      tailRaw.setRange(tailOffset, tailOffset + chunk.length, chunk);
      tailOffset += chunk.length;
    }
    final tailStr = utf8.decode(tailRaw);

    final sb = StringBuffer(headStr)
      ..writeln()
      ..write('[... truncated $dropped bytes ...]')
      ..writeln()
      ..write(tailStr);

    return (sb.toString(), true);
  }

  static List<int> _encodeRune(int cp) {
    if (cp < 0x80) return [cp];
    if (cp < 0x800) {
      return [0xC0 | (cp >> 6), 0x80 | (cp & 0x3F)];
    }
    if (cp < 0x10000) {
      return [
        0xE0 | (cp >> 12),
        0x80 | ((cp >> 6) & 0x3F),
        0x80 | (cp & 0x3F),
      ];
    }
    return [
      0xF0 | (cp >> 18),
      0x80 | ((cp >> 12) & 0x3F),
      0x80 | ((cp >> 6) & 0x3F),
      0x80 | (cp & 0x3F),
    ];
  }
}

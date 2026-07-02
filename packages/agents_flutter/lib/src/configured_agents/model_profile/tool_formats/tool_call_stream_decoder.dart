// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'tool_format.dart';

/// An incremental splitter for families whose tool calls begin at a single
/// open marker and run to the end of the turn.
///
/// Feed streamed pieces to [add], which returns any prose that is safely
/// before the marker; once the marker is seen everything is buffered.
/// Call [finish] at stream end to parse the buffered tail. A
/// [FormatException] from the parser (truncated or malformed call)
/// surfaces the raw tail as prose rather than erroring the whole turn.
///
/// Stateful and single-use per response stream.
class ToolCallStreamDecoder {
  /// Creates a decoder that buffers on [openMarker] and delegates to
  /// [parse].
  ToolCallStreamDecoder({required this.openMarker, required this.parse});

  /// The literal marker that begins a tool-call region.
  final String openMarker;

  /// Parses a buffered tail (which begins with [openMarker]) into a turn.
  final ParsedToolTurn Function(String generated) parse;

  var _buf = '';
  final _tail = StringBuffer();
  var _buffering = false;

  /// Consumes one streamed [piece]; returns prose ready to emit.
  ///
  /// Holds back marker-length-minus-one trailing characters so a marker
  /// straddling two pieces is never emitted as prose.
  String add(String piece) {
    if (_buffering) {
      _tail.write(piece);
      return '';
    }
    _buf += piece;

    final at = _buf.indexOf(openMarker);
    if (at >= 0) {
      final prose = _buf.substring(0, at);
      _tail.write(_buf.substring(at));
      _buf = '';
      _buffering = true;
      return prose;
    }
    final holdback = openMarker.length - 1;
    if (_buf.length > holdback) {
      final emit = _buf.substring(0, _buf.length - holdback);
      _buf = _buf.substring(_buf.length - holdback);
      return emit;
    }
    return '';
  }

  /// Ends the stream: parses any buffered tool-call tail.
  ///
  /// The returned turn carries held-back or trailing prose in
  /// [ParsedToolTurn.text] and the parsed calls, if any.
  ParsedToolTurn finish() {
    if (!_buffering) {
      return ParsedToolTurn(text: _buf, calls: const []);
    }
    try {
      return parse(_tail.toString());
    } on FormatException {
      return ParsedToolTurn(text: _tail.toString(), calls: const []);
    }
  }
}

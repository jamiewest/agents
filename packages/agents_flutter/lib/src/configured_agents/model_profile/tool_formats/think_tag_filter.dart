// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:extensions/ai.dart';

/// An incremental filter that lifts `<think>…</think>` regions out of
/// streamed text into [TextReasoningContent].
///
/// Reasoning-tuned models (Qwen3, QwQ, DeepSeek-R1) open their turn with a
/// think block; some emit several. Feed each streamed piece to [add] and
/// emit the returned contents in order; call [flush] once the stream ends
/// to drain held-back characters. An unterminated think block is surfaced
/// as reasoning rather than lost.
///
/// The filter is stateful and single-use per response stream.
class ThinkTagFilter {
  /// Creates a filter for the given tag pair.
  ThinkTagFilter({this.openTag = '<think>', this.closeTag = '</think>'});

  /// The literal tag that opens a reasoning region.
  final String openTag;

  /// The literal tag that closes a reasoning region.
  final String closeTag;

  var _buf = '';
  var _inThink = false;

  /// Consumes one streamed [piece] and returns the contents it completes.
  List<AIContent> add(String piece) {
    _buf += piece;
    final out = <AIContent>[];
    var progressed = true;
    while (progressed) {
      progressed = _inThink ? _drainThink(out) : _drainText(out);
    }
    return out;
  }

  /// Drains any remaining held-back text once the stream has ended.
  List<AIContent> flush() {
    final out = <AIContent>[];
    if (_buf.isNotEmpty) {
      out.add(_inThink ? TextReasoningContent(_buf) : TextContent(_buf));
      _buf = '';
    }
    return out;
  }

  /// Emits text up to a complete or possible [openTag]; returns whether a
  /// full tag was consumed (so scanning should continue).
  bool _drainText(List<AIContent> out) {
    final at = _buf.indexOf(openTag);
    if (at >= 0) {
      final text = _buf.substring(0, at);
      if (text.isNotEmpty) out.add(TextContent(text));
      _buf = _buf.substring(at + openTag.length);
      _inThink = true;
      return true;
    }
    final holdback = openTag.length - 1;
    if (_buf.length > holdback) {
      final emit = _buf.substring(0, _buf.length - holdback);
      if (emit.isNotEmpty) out.add(TextContent(emit));
      _buf = _buf.substring(_buf.length - holdback);
    }
    return false;
  }

  /// Emits reasoning up to a complete or possible [closeTag]; returns
  /// whether a full tag was consumed.
  bool _drainThink(List<AIContent> out) {
    final at = _buf.indexOf(closeTag);
    if (at >= 0) {
      final thought = _buf.substring(0, at);
      if (thought.isNotEmpty) out.add(TextReasoningContent(thought));
      _buf = _buf.substring(at + closeTag.length);
      _inThink = false;
      return true;
    }
    final holdback = closeTag.length - 1;
    if (_buf.length > holdback) {
      final emit = _buf.substring(0, _buf.length - holdback);
      if (emit.isNotEmpty) out.add(TextReasoningContent(emit));
      _buf = _buf.substring(_buf.length - holdback);
    }
    return false;
  }
}

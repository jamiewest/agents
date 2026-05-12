import 'dart:async';

import 'package:extensions/system.dart';

/// Synchronises the workflow run loop with external input events.
///
/// Works as a binary semaphore: [signalInput] releases one waiting call to
/// [waitForInputAsync]. A second [signalInput] before the first wait resolves
/// is silently ignored.
final class InputWaiter {
  Completer<void> _completer = Completer<void>();

  /// Signals that new input is available.
  ///
  /// Safe to call more than once before [waitForInputAsync] returns; extra
  /// signals are swallowed.
  void signalInput() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  /// Waits until [signalInput] is called, or until [cancellationToken] fires.
  Future<void> waitForInputAsync({CancellationToken? cancellationToken}) async {
    cancellationToken?.throwIfCancellationRequested();
    await _completer.future;
    _completer = Completer<void>();
  }
}

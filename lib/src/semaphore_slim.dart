import 'dart:async';
import 'package:extensions/system.dart';

/// A Dart port of .NET's SemaphoreSlim for async mutual exclusion.
///
/// In Dart's single-threaded model this is a cooperative async lock.
class SemaphoreSlim {
  SemaphoreSlim(int initialCount, [int? maxCount]) : _count = initialCount;

  int _count;
  final _waiters = <Completer<void>>[];

  /// Acquires the semaphore, waiting asynchronously if not available.
  Future<void> waitAsync([CancellationToken? cancellationToken]) async {
    if (_count > 0) {
      _count--;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }

  /// Releases the semaphore, allowing one waiting caller to proceed.
  void release() {
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeAt(0);
      next.complete();
    } else {
      _count++;
    }
  }

  /// Releases resources held by this semaphore.
  void dispose() {
    for (final w in _waiters) {
      if (!w.isCompleted) w.completeError(StateError('SemaphoreSlim disposed'));
    }
    _waiters.clear();
  }
}

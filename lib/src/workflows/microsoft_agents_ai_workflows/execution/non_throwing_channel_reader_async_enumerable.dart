import 'package:extensions/system.dart';

/// Wraps a [Stream] and absorbs [OperationCanceledException]s so iteration
/// completes normally when cancelled rather than propagating the exception.
///
/// Maps C#'s [NonThrowingChannelReaderAsyncEnumerable<T>], which wraps a
/// [ChannelReader<T>.ReadAllAsync()] pipeline and catches
/// [OperationCanceledException].
final class NonThrowingChannelReaderAsyncEnumerable<T> {
  /// Creates an adapter around [source].
  const NonThrowingChannelReaderAsyncEnumerable(this._source);

  final Stream<T> _source;

  /// Returns a [Stream] that completes normally when [_source] is cancelled.
  Stream<T> asStream() => _wrap(_source);

  static Stream<T> _wrap<T>(Stream<T> source) async* {
    try {
      await for (final item in source) {
        yield item;
      }
    } on OperationCanceledException {
      // Complete normally on cancellation.
    }
  }
}

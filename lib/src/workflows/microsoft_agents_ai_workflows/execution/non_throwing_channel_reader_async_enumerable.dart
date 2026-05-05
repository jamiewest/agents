import 'package:extensions/system.dart';
/// A custom IAsyncEnumerable implementation that reads from a ChannelReader,
/// and suppresses OperationCanceledException when the cancellation token is
/// triggered.
class NonThrowingChannelReaderAsyncEnumerable<T> implements Stream<T> {
  /// A custom IAsyncEnumerable implementation that reads from a ChannelReader,
  /// and suppresses OperationCanceledException when the cancellation token is
  /// triggered.
  const NonThrowingChannelReaderAsyncEnumerable(ChannelReader<T> reader);

  /// Returns an async enumerator that reads items from the channel. If
  /// cancellation is requested, the enumeration exits silently without
  /// throwing.
  ///
  /// Returns: An async enumerator over the channel items.
  ///
  /// [cancellationToken] An optional cancellation token from the caller.
  @override
  AsyncEnumerator<T> getAsyncEnumerator({CancellationToken? cancellationToken}) {
    return enumerator(reader, cancellationToken);
  }
}
class Enumerator implements AsyncEnumerator<T> {
  const Enumerator(ChannelReader<T> reader, CancellationToken cancellationToken, );

  late T current;

  @override
  Future dispose() {
    return Future.value();
  }

  /// Moves to the next item in the channel.
  ///
  /// Returns: If successful, returns `true`, otherwise `false`.
  @override
  Future<bool> moveNext() async  {
    try {
      var hasData = await reader.waitToReadAsync(cancellationToken);
      if (hasData) {
        this.current = await reader.readAsync(cancellationToken);
        return true;
      }
    } catch (e, s) {
      if (e is OperationCanceledException) {
        final  = e as OperationCanceledException;
        {}
      } else {
        rethrow;
      }
    }
    return false;
  }
}

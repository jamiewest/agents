import 'package:extensions/system.dart';
import '../../../semaphore_slim.dart';
class InputWaiter implements Disposable {
  InputWaiter();

  final SemaphoreSlim _inputSignal = SemaphoreSlim(0, 1);

  @override
  void dispose() {
    this._inputSignal.dispose();
  }

  /// Signals that new input has been provided and the waiter should continue
  /// processing. Called by AsyncRunHandle when the user enqueues a message or
  /// response.
  void signalInput() {
    try {
      this._inputSignal.release();
    } catch (e, s) {
      if (e is SemaphoreFullException) {
        final  = e as SemaphoreFullException;
        {}
      } else {
        rethrow;
      }
    }
  }

  Future waitForInput({Duration? timeout, CancellationToken? cancellationToken, }) async  {
    await this._inputSignal.waitAsync(
      timeout ?? TimeSpan.fromMilliseconds(-1),
      cancellationToken,
    ) ;
  }
}

import 'package:extensions/ai.dart';
import '../../../func_typedefs.dart';
import '../protocol_builder.dart';
import '../resettable_executor.dart';

/// Provides an executor that accepts the output messages from each of the
/// concurrent agents and produces a result list containing the last message
/// from each.
class ConcurrentEndExecutor extends Executor implements ResettableExecutor {
  ConcurrentEndExecutor(
    int expectedInputs,
    Func<List<List<ChatMessage>>, List<ChatMessage>> aggregator,
  ) :
      _expectedInputs = expectedInputs,
      _aggregator = aggregator {
    this._allResults = List<List<ChatMessage>>(expectedInputs);
    this._remaining = expectedInputs;
  }

  final int _expectedInputs;

  final Func<List<List<ChatMessage>>, List<ChatMessage>> _aggregator;

  List<List<ChatMessage>> _allResults;

  late int _remaining;

  void reset() {
    this._allResults = List<List<ChatMessage>>(this._expectedInputs);
    this._remaining = this._expectedInputs;
  }

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    protocolBuilder.routeBuilder.addHandler<List<ChatMessage>>(async (messages, context, cancellationToken) =>
        {
            // TODO: https://github.com/microsoft/agent-framework/issues/784
            // This locking should not be necessary.
            bool done;
            lock (this._allResults)
            {
                this._allResults.add(messages);
                done = --this._remaining == 0;
      }

            if (done)
            {
                this._remaining = this._expectedInputs;

                var results = this._allResults;
                this._allResults = List<List<ChatMessage>>(this._expectedInputs);
                await context.yieldOutput(
                  this._aggregator(results),
                  cancellationToken,
                ) ;
      }
        });
    return protocolBuilder.yieldsOutput<List<ChatMessage>>();
  }

  @override
  Future resetAsync() {
    this.reset();
    return Future.value();
  }
}

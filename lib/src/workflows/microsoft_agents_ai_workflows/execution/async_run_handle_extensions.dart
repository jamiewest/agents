import 'package:extensions/system.dart';
import '../run.dart';
import '../streaming_run.dart';
import 'async_run_handle.dart';

extension AsyncRunHandleExtensions on AsyncRunHandle {Future<StreamingRun> enqueueAndStream<TInput>(
  TInput input,
  {CancellationToken? cancellationToken, }
) async {
await runHandle.enqueueMessageAsync(input, cancellationToken);
return new(runHandle);
 }
Future<StreamingRun> enqueueUntypedAndStream(
  Object input,
  {CancellationToken? cancellationToken, }
) async {
await runHandle.enqueueMessageUntypedAsync(
  input,
  cancellationToken: cancellationToken,
) ;
return new(runHandle);
 }
Future<Run> enqueueAndRun<TInput>(TInput input, {CancellationToken? cancellationToken, }) async {
await runHandle.enqueueMessageAsync(input, cancellationToken);
var run = new(runHandle);
await run.runToNextHaltAsync(cancellationToken);
return run;
 }
Future<Run> enqueueUntypedAndRun(Object input, {CancellationToken? cancellationToken, }) async {
await runHandle.enqueueMessageUntypedAsync(
  input,
  cancellationToken: cancellationToken,
) ;
var run = new(runHandle);
await run.runToNextHaltAsync(cancellationToken);
return run;
 }
 }

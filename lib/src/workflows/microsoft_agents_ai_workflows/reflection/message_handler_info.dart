import 'package:extensions/system.dart';
import '../../../func_typedefs.dart';
import '../execution/call_result.dart';
import '../workflow_context.dart';
import 'reflecting_executor.dart';
import 'value_task_type_erasure.dart';

class MessageHandlerInfo {
  MessageHandlerInfo(MethodInfo handlerInfo) : handlerInfo = handlerInfo {
    // The method is one of the following:
        //   - ValueTask handleAsync(TMessage message, IExecutionContext context)
        //   - ValueTask<TResult> handleAsync(TMessage message, IExecutionContext context)
    var parameters = handlerInfo.getParameters();
    if (parameters.length != 3) {
      throw ArgumentError(
        'Handler method must have exactly three parameters: TMessage, IWorkflowContext, and CancellationToken.',
        'handlerInfo',
      );
    }
    if (parameters[1].parameterType != IWorkflowContext) {
      throw ArgumentError(
        "Handler method's second parameter must be of type IWorkflowContext.",
        'handlerInfo',
      );
    }
    if (parameters[2].parameterType != CancellationToken) {
      throw ArgumentError(
        "Handler method's third parameter must be of type CancellationToken.",
        'handlerInfo',
      );
    }
    this.inType = parameters[0].parameterType;
    var decoratedReturnType = handlerInfo.returnType;
    if (decoratedReturnType.isGenericType && decoratedReturnType.getGenericTypeDefinition() == ValueTask<>) {
      var returnRawTypes = decoratedReturnType.getGenericArguments();
      assert(
                returnRawTypes.length == 1,
                "ValueTask<TResult> should have exactly one generic argument.");
      this.outType = returnRawTypes.single();
      this.unwrapper = ValueTaskTypeErasure.unwrapperFor(this.outType);
    } else if (decoratedReturnType == ValueTask) {
      // If the return type is ValueTask, there is no output type.
            this.outType = null;
    } else {
      throw ArgumentError(
        "Handler method must return ValueTask or ValueTask<TResult>.",
        'handlerInfo',
      );
    }
  }

  late Type inType;

  late Type? outType;

  MethodInfo handlerInfo;

  Func<Object, Future<Object?>>? unwrapper;

  static Func3<Object, WorkflowContext, CancellationToken, Future<CallResult>> bind(
    bool checkType,
    {Func3<Object, WorkflowContext, CancellationToken, Object?>? handlerAsync, Type? resultType, Func<Object, Future<Object?>>? unwrapper, ReflectingExecutor<TExecutor>? executor, }
  ) {
    return InvokeHandlerAsync;
    /* TODO: unsupported node kind "unknown" */
    // async ValueTask<CallResult> InvokeHandlerAsync(Object message, IWorkflowContext workflowContext, CancellationToken cancellationToken)
    //         {
      //             bool expectingVoid = resultType is null || resultType == void;
      //
      //             try
      //             {
        //                 Object? maybeValueTask = handlerAsync(message, workflowContext, cancellationToken);
        //
        //                 if (expectingVoid)
        //                 {
          //                     if (maybeValueTask is ValueTask)
          //                     {
            //                         await vt;
            //                         return CallResult.ReturnVoid();
            //                     }
          //
          //                     throw new InvalidOperationException(
          //                         "Handler method is expected to return ValueTask or ValueTask<TResult>, but returned " +
          //                         $"{maybeValueTask?.GetType().Name ?? "null"}.");
          //                 }
        //
        //                 Debug.Assert(resultType is not null, "Expected resultType to be non-null when not expecting void.");
        //                 if (unwrapper is null)
        //                 {
          //                     throw new InvalidOperationException(
          //                         $"Handler method is expected to return ValueTask<{resultType!.Name}>, but no unwrapper is available.");
          //                 }
        //
        //                 if (maybeValueTask is null)
        //                 {
          //                     throw new InvalidOperationException(
          //                         $"Handler method returned null, but a ValueTask<{resultType!.Name}> was expected.");
          //                 }
        //
        //                 Object? result = await unwrapper(maybeValueTask);
        //
        //                 if (checkType && result is not null && !resultType.IsInstanceOfType(result))
        //                 {
          //                     throw new InvalidOperationException(
          //                         $"Handler method returned an incompatible type: expected {resultType.Name}, got {result.GetType().Name}.");
          //                 }
        //
        //                 return CallResult.ReturnResult(result);
        //             }
      //             catch (OperationCanceledException)
      //             {
        //                 // If the operation was canceled, return a canceled CallResult.
        //                 return CallResult.Cancelled(wasVoid: expectingVoid);
        //             }
      //             catch (Exception ex)
      //             {
        //                 // If the handler throws an exception, return it in the CallResult.
        //                 return CallResult.RaisedException(wasVoid: expectingVoid, exception: ex);
        //             }
      //         }
  }
}

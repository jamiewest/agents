import '../../../func_typedefs.dart';

extension TaskReflection on Type {MethodInfo reflectResult_get() {
assert(specializedType.isGenericType &&
                     specializedType.getGenericTypeDefinition() == Task<>, "specializedType must be a ValueTask<> type.");
return specializedType.getMethodFromGenericMethodDefinition(Result_get);
 }
bool isFutureType() {
return type.isGenericType && type.getGenericTypeDefinition() == Task<>;
 }
 }
extension ValueTaskReflection on Type {MethodInfo reflectAsFuture() {
assert(specializedType.isGenericType &&
                     specializedType.getGenericTypeDefinition() == ValueTask<>, "specializedType must be a ValueTask<> type.");
return specializedType.getMethodFromGenericMethodDefinition(AsTask);
 }
bool isValueFutureType() {
return type.isGenericType && type.getGenericTypeDefinition() == ValueTask<>;
 }
 }
class ValueTaskTypeErasure {
  ValueTaskTypeErasure();

  static Func<Object, Future<Object?>> unwrapperFor(Type expectedResultType) {
    return UnwrapAndEraseAsync;
    /* TODO: unsupported node kind "unknown" */
    // async ValueTask<Object?> UnwrapAndEraseAsync(Object maybeGenericVT)
    //         {
      //             // This method handles only ValueTask<TResult> types.
      //             Type maybeVTType = maybeGenericVT.GetType();
      //
      //             if (!maybeVTType.IsValueTaskType())
      //             {
        //                 throw new InvalidOperationException($"Expected ValueTask or ValueTask<{expectedResultType.Name}>, but got {maybeGenericVT.GetType().Name}.");
        //             }
      //
      //             MethodInfo asTaskMethod = maybeVTType.ReflectAsTask();
      //             Debug.Assert(asTaskMethod.ReturnType.IsTaskType(), "AsTask must return a Task<> type.");
      //
      //             MethodInfo getResultMethod = asTaskMethod.ReturnType.ReflectResult_get();
      //             Type actualResultType = getResultMethod.ReturnType;
      //
      //             if (!expectedResultType.IsAssignableFrom(actualResultType))
      //             {
        //                 throw new InvalidOperationException($"Expected ValueTask<{expectedResultType.Name}> or a compatible type, but got ValueTask<{actualResultType.Name}>.");
        //             }
      //
      //             Task task = (Task)asTaskMethod.ReflectionInvoke(maybeGenericVT)!;
      //             await task; // TODO: Could we need to capture the context here?
      //             return getResultMethod.ReflectionInvoke(task);
      //         }
  }
}

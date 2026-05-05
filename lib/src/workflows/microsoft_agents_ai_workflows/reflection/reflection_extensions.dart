class ReflectionDemands {
  ReflectionDemands();
}

extension ReflectionExtensions on MethodInfo {
  Object? reflectionInvoke(Object? target, List<Object?> arguments) {
    try {
      return method.invoke(
        target,
        BindingFlags.defaultValue,
        binder: null,
        arguments,
        culture: null,
      );
    } catch (e, s) {
      if (e is TargetInvocationException) {
        final e = e as TargetInvocationException;
        {
          // If we're targeting .net Framework, such that BindingFlags.doNotWrapExceptions
          // is ignored, the original exception will be wrapped in a TargetInvocationException.
          // Unwrap it and throw that original exception, maintaining its stack information.
          System.runtime.exceptionServices.exceptionDispatchInfo
              .capture(e.innerException)
              .throwValue();
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  MethodInfo getMethodFromGenericMethodDefinition(
    MethodInfo genericMethodDefinition,
  ) {
    assert(
      specializedType.isGenericType &&
          specializedType.getGenericTypeDefinition() ==
              genericMethodDefinition.declaringType,
      "generic member definition doesn't match type.",
    );
    var All =
        BindingFlags.public |
        BindingFlags.nonPublic |
        BindingFlags.staticValue |
        BindingFlags.instance;
    return specializedType
        .getMethods(All)
        .first((m) => m.metadataToken == genericMethodDefinition.metadataToken);
  }
}

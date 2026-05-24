/// Generic function type aliases ported from C# delegate conventions.
typedef Func<TIn, TOut> = TOut Function(TIn);

/// A function that takes two arguments and returns [TOut].
typedef Func2<T1, T2, TOut> = TOut Function(T1, T2);

/// A function that takes three arguments and returns [TOut].
typedef Func3<T1, T2, T3, TOut> = TOut Function(T1, T2, T3);

/// A function that takes four arguments and returns [TOut].
typedef Func4<T1, T2, T3, T4, TOut> = TOut Function(T1, T2, T3, T4);

/// A zero-argument void callback.
typedef Action = void Function();

/// A single-argument void callback.
typedef Action1<T> = void Function(T);

/// A two-argument void callback.
typedef Action2<T1, T2> = void Function(T1, T2);

/// A three-argument void callback.
typedef Action3<T1, T2, T3> = void Function(T1, T2, T3);

/// A four-argument void callback.
typedef Action4<T1, T2, T3, T4> = void Function(T1, T2, T3, T4);

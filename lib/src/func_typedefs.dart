/// Generic function type aliases ported from C# delegate conventions.
typedef Func<TIn, TOut> = TOut Function(TIn);
typedef Func2<T1, T2, TOut> = TOut Function(T1, T2);
typedef Func3<T1, T2, T3, TOut> = TOut Function(T1, T2, T3);
typedef Func4<T1, T2, T3, T4, TOut> = TOut Function(T1, T2, T3, T4);
typedef Action = void Function();
typedef Action1<T> = void Function(T);
typedef Action2<T1, T2> = void Function(T1, T2);
typedef Action3<T1, T2, T3> = void Function(T1, T2, T3);
typedef Action4<T1, T2, T3, T4> = void Function(T1, T2, T3, T4);

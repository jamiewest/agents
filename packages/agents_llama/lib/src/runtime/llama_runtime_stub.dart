import 'llama_runtime_api.dart';

/// Creates a platform runtime.
LlamaRuntime createLlamaRuntime() => throw UnsupportedError(
  'Local llama inference is not supported on this platform.',
);

/// Controls how workflow events are streamed during execution.
enum ExecutionMode {
  /// Normal streaming mode — events stream out immediately as they are created.
  offThread,

  /// Lockstep mode — events are batched and emitted after each superstep.
  lockstep,

  /// Subworkflow mode — like [offThread] but supersteps are driven externally
  /// by the hosting workflow rather than an internal task.
  subworkflow,
}

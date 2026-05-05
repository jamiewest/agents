enum ExecutionMode {
  /// Normal streaming mode using the new channel-based implementation. Events
  /// stream as they are created.
  offThread,

  /// Lockstep mode where events are batched per superstep. Events are
  /// accumulated and emitted after each superstep completes.
  lockstep,

  /// A special execution mode for subworkflows - it functions like OffThread,
  /// but without the internal task running super steps, as they are implemented
  /// by being driven directly by the hosting workflow
  subworkflow,
}

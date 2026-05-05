import 'package:extensions/ai.dart';

/// Provides optional parameters and configuration settings for controlling
/// agent run behavior.
///
/// Remarks: Implementations of [AIAgent] may provide subclasses of
/// [AgentRunOptions] with additional options specific to that agent type.
class AgentRunOptions {
  /// Creates a default [AgentRunOptions] instance with no preset values.
  AgentRunOptions();

  /// Initializes a new instance of the [AgentRunOptions] class by copying
  /// values from the specified options.
  ///
  /// [options] The options instance from which to copy values.
  AgentRunOptions.copyFrom(AgentRunOptions options) {
    continuationToken = options.continuationToken;
    allowBackgroundResponses = options.allowBackgroundResponses;
    additionalProperties = options.additionalProperties != null
        ? Map<String, Object?>.of(options.additionalProperties!)
        : null;
    responseFormat = options.responseFormat;
  }

  /// Gets or sets the continuation token for resuming and getting the result of
  /// the agent response identified by this token.
  ///
  /// Remarks: This property is used for background responses that can be
  /// activated via the [AllowBackgroundResponses] property if the [AIAgent]
  /// implementation supports them. Streamed background responses, such as those
  /// returned by default by [CancellationToken)] can be resumed if interrupted.
  /// This means that a continuation token obtained from the [ContinuationToken]
  /// of an update just before the interruption occurred can be passed to this
  /// property to resume the stream from the point of interruption. Non-streamed
  /// background responses, such as those returned by [CancellationToken)], can
  /// be polled for completion by obtaining the token from the
  /// [ContinuationToken] property and passing it via this property on
  /// subsequent calls to [CancellationToken)].
  ResponseContinuationToken? continuationToken;

  /// Gets or sets a value indicating whether the background responses are
  /// allowed.
  ///
  /// Remarks: Background responses allow running long-running operations or
  /// tasks asynchronously in the background that can be resumed by streaming
  /// APIs and polled for completion by non-streaming APIs. When this property
  /// is set to true, non-streaming APIs may start a background operation and
  /// return an initial response with a continuation token. Subsequent calls to
  /// the same API should be made in a polling manner with the continuation
  /// token to get the final result of the operation. When this property is set
  /// to true, streaming APIs may also start a background operation and begin
  /// streaming response updates until the operation is completed. If the
  /// streaming connection is interrupted, the continuation token obtained from
  /// the last update that has one should be supplied to a subsequent call to
  /// the same streaming API to resume the stream from the point of interruption
  /// and continue receiving updates until the operation is completed. This
  /// property only takes effect if the implementation it's used with supports
  /// background responses. If the implementation does not support background
  /// responses, this property will be ignored.
  bool? allowBackgroundResponses;

  /// Gets or sets additional properties associated with these options.
  ///
  /// Remarks: Additional properties provide a way to include custom metadata or
  /// provider-specific information that doesn't fit into the standard options
  /// schema. This is useful for preserving implementation-specific details or
  /// extending the options with custom data.
  AdditionalPropertiesDictionary? additionalProperties;

  /// Gets or sets the response format.
  ///
  /// Remarks: If `null`, no response format is specified and the agent will use
  /// its default. This property can be set to [Text] to specify that the
  /// response should be unstructured text, to [Json] to specify that the
  /// response should be structured JSON data, or an instance of
  /// [ChatResponseFormatJson] constructed with a specific JSON schema to
  /// request that the response be structured JSON data according to that
  /// schema. It is up to the agent implementation if or how to honor the
  /// request. If the agent implementation doesn't recognize the specific kind
  /// of [ChatResponseFormat], it can be ignored.
  ChatResponseFormat? responseFormat;

  /// Produces a clone of the current [AgentRunOptions] instance.
  ///
  /// Remarks: The clone will have the same values for all properties as the
  /// original instance. Any collections, like [AdditionalProperties], are
  /// shallow-cloned, meaning a new collection instance is created, but any
  /// references contained by the collections are shared with the original.
  /// Derived types should override [Clone] to return an instance of the derived
  /// type.
  ///
  /// Returns: A clone of the current [AgentRunOptions] instance.
  AgentRunOptions clone() => AgentRunOptions.copyFrom(this);
}

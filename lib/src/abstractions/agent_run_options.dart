import 'package:extensions/ai.dart';

/// Optional parameters and configuration settings for controlling agent run
/// behavior.
///
/// [AIAgent] implementations may provide subclasses with additional options
/// specific to that agent type.
class AgentRunOptions {
  /// Creates a default [AgentRunOptions] instance with no preset values.
  AgentRunOptions();

  /// Creates an [AgentRunOptions] by copying values from [options].
  AgentRunOptions.copyFrom(AgentRunOptions options) {
    continuationToken = options.continuationToken;
    allowBackgroundResponses = options.allowBackgroundResponses;
    additionalProperties = options.additionalProperties != null
        ? Map<String, Object?>.of(options.additionalProperties!)
        : null;
    responseFormat = options.responseFormat;
  }

  /// Continuation token for resuming a background agent response.
  ///
  /// Used with [allowBackgroundResponses]. For streaming responses, a token
  /// captured from the last received update can be supplied here to resume the
  /// stream from the point of interruption. For non-streaming responses, supply
  /// the token on subsequent polling calls to retrieve the final result.
  ResponseContinuationToken? continuationToken;

  /// Whether background (asynchronous) responses are allowed.
  ///
  /// When `true`, non-streaming APIs may return an initial response with a
  /// [continuationToken] that can be used in polling calls to retrieve the
  /// final result. Streaming APIs may likewise start a background operation and
  /// emit updates until completion; if the connection is interrupted, the last
  /// received [continuationToken] can resume the stream. Has no effect if the
  /// underlying implementation does not support background responses.
  bool? allowBackgroundResponses;

  /// Additional provider-specific metadata that does not fit the standard
  /// options schema.
  AdditionalPropertiesDictionary? additionalProperties;

  /// The desired response format, or `null` to use the agent's default.
  ///
  /// Set to a [ChatResponseFormat] text variant for unstructured text, a JSON
  /// variant for structured JSON, or a [ChatResponseFormatJson] with a schema
  /// for schema-constrained JSON. The agent implementation may ignore formats
  /// it does not recognise.
  ChatResponseFormat? responseFormat;

  /// A shallow clone of this [AgentRunOptions].
  ///
  /// Collection properties such as [additionalProperties] are shallow-cloned:
  /// a new collection is created but contained references are shared. Derived
  /// types should override this to return an instance of their own type.
  AgentRunOptions clone() => AgentRunOptions.copyFrom(this);
}

import 'output_tag.dart';

/// Provides JSON encode/decode helpers for [OutputTag] that map a tag to and
/// from its string [OutputTag.value].
class OutputTagJsonConverter {
  OutputTagJsonConverter._();

  /// Encodes [tag] to its string value.
  static String encode(OutputTag tag) => tag.value;

  /// Decodes a string value to an [OutputTag], reusing well-known singletons.
  static OutputTag decode(String value) => OutputTag.fromValue(value);
}

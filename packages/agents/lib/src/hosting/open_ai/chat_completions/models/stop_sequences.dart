// Copyright (c) Microsoft. All rights reserved.
//
// Ported from ChatCompletions/Models/StopSequences.cs.

/// Up to four sequences where the API will stop generating further tokens.
///
/// Wire form is either a single string or an array of strings.
class StopSequences {
  const StopSequences._(this._single, this._sequences);

  /// Creates a [StopSequences] from a single string.
  factory StopSequences.fromString(String value) =>
      StopSequences._(value, null);

  /// Creates a [StopSequences] from a list of strings.
  factory StopSequences.fromSequences(List<String> sequences) =>
      StopSequences._(null, sequences);

  /// Parses a [StopSequences] from JSON (string or array).
  factory StopSequences.fromJson(Object? json) {
    if (json is String) {
      return StopSequences.fromString(json);
    }
    if (json is List) {
      return StopSequences.fromSequences(json.cast<String>());
    }
    throw FormatException('Unexpected StopSequences JSON: $json');
  }

  final String? _single;
  final List<String>? _sequences;

  /// The normalized list of stop sequences, regardless of wire form.
  List<String> get sequenceList =>
      _sequences ?? (_single != null ? [_single] : const []);

  /// Serializes this value back to its wire form (string or array).
  Object toJson() => _single ?? _sequences!;
}

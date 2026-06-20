// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Microsoft.Agents.AI.Hosting.OpenAI/Models/SortOrder.cs.

/// Specifies the sort order for list operations.
///
/// Serializes to the OpenAI wire values `asc` and `desc`.
enum SortOrder {
  /// Sort in ascending order (oldest to newest).
  ascending('asc'),

  /// Sort in descending order (newest to oldest).
  descending('desc');

  const SortOrder(this.wireValue);

  /// The OpenAI wire representation (`asc` / `desc`).
  final String wireValue;

  /// Serializes this value to its wire string.
  String toJson() => wireValue;

  /// Parses a wire string (`asc` / `desc`, case-insensitive) to a [SortOrder].
  ///
  /// Throws [FormatException] when [value] is null or unrecognized.
  static SortOrder fromJson(String? value) {
    switch (value?.toLowerCase()) {
      case 'asc':
        return SortOrder.ascending;
      case 'desc':
        return SortOrder.descending;
      case null:
        throw const FormatException('SortOrder value cannot be null');
      default:
        throw FormatException('Invalid SortOrder value: $value');
    }
  }
}

// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Microsoft.Agents.AI.Hosting.OpenAI/Models/ListResponse.cs.

/// Generic list response for paginated results.
///
/// Used across the OpenAI API for listing resources.
class ListResponse<T> {
  /// Creates a [ListResponse].
  const ListResponse({
    required this.data,
    required this.hasMore,
    this.firstId,
    this.lastId,
  });

  /// The list of items.
  final List<T> data;

  /// Whether there are more items available.
  final bool hasMore;

  /// The ID of the first item in the list.
  final String? firstId;

  /// The ID of the last item in the list.
  final String? lastId;

  /// The object type, always `list`.
  String get object => 'list';

  /// Serializes this list, using [itemToJson] to serialize each element.
  Map<String, dynamic> toJson(Object? Function(T item) itemToJson) {
    return <String, dynamic>{
      'object': object,
      'data': data.map(itemToJson).toList(),
      if (firstId != null) 'first_id': firstId,
      if (lastId != null) 'last_id': lastId,
      'has_more': hasMore,
    };
  }
}

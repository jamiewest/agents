// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/Models/ItemResource.cs.
//
// Design note: upstream models ~25 polymorphic `ItemResource` subtypes. This
// port collapses them into a single JSON-backed value object keyed by its
// `type` discriminator. Conversation storage treats items opaquely (store /
// list / get / delete), so this preserves the full wire contract for every
// item type — including exotic ones (computer/web-search/MCP/...) — without a
// large class hierarchy. The Responses surface may later add typed accessors.

/// A conversation/response item, identified by [id] and discriminated by [type].
class ItemResource {
  /// Creates an [ItemResource] backed by its raw JSON [data].
  ItemResource({
    required this.id,
    required this.type,
    required Map<String, dynamic> data,
  }) : _data = data;

  /// Parses an [ItemResource] from a decoded JSON object.
  factory ItemResource.fromJson(Map<String, dynamic> json) => ItemResource(
    id: json['id'] as String? ?? '',
    type: json['type'] as String,
    data: json,
  );

  /// The server-assigned item ID.
  final String id;

  /// The item type discriminator (for example `message`, `function_call`).
  final String type;

  final Map<String, dynamic> _data;

  /// The full backing JSON for this item (includes `id` and `type`).
  Map<String, dynamic> toJson() => _data;
}

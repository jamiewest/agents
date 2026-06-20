// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/Models/ItemParam.cs and ItemParamExtensions.cs.
//
// Like [ItemResource], the ~20 polymorphic `ItemParam` subtypes are collapsed
// into a single JSON-backed value object keyed by `type`. `ItemParam` carries
// no `id`; the server generates one when converting to an [ItemResource].

import '../../id_generator.dart';
import 'item_resource.dart';

/// An input item for creating conversation items or response inputs.
class ItemParam {
  /// Creates an [ItemParam] backed by its raw JSON [data].
  ItemParam({required this.type, required Map<String, dynamic> data})
    : _data = data;

  /// Parses an [ItemParam] from a decoded JSON object.
  factory ItemParam.fromJson(Map<String, dynamic> json) =>
      ItemParam(type: json['type'] as String, data: json);

  /// The item type discriminator.
  final String type;

  final Map<String, dynamic> _data;

  /// The full backing JSON for this parameter.
  Map<String, dynamic> toJson() => _data;

  /// Item types that gain a `completed` status when materialized.
  static const _statusBearingTypes = {
    'message',
    'function_call',
    'function_call_output',
  };

  /// Materializes this parameter into an [ItemResource] with a generated ID.
  ///
  /// Mirrors `ItemParamExtensions.ToItemResource`: a server ID is assigned and
  /// message/function items receive a default `completed` status.
  ItemResource toItemResource(IdGenerator idGenerator) {
    final data = <String, dynamic>{'id': idGenerator.generateMessageId()}
      ..addAll(_data);
    if (_statusBearingTypes.contains(type)) {
      data.putIfAbsent('status', () => 'completed');
    }
    return ItemResource.fromJson(data);
  }
}

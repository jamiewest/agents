import '../output_tag.dart';

/// JSON converter for `WorkflowInfo.outputExecutors` that supports both the
/// new map shape (`{ "id": ["intermediate"] }`) and the legacy array shape
/// (`["id1", "id2"]`). Legacy-shaped payloads are read as if every id had been
/// registered as a regular (untagged) output source; output is always written
/// in the new map shape.
class WorkflowInfoOutputExecutorsConverter {
  WorkflowInfoOutputExecutorsConverter._();

  /// Encodes [value] to the map shape.
  static Map<String, Object?> encode(Map<String, Set<OutputTag>> value) => {
    for (final entry in value.entries)
      entry.key: [for (final tag in entry.value) tag.value],
  };

  /// Decodes either the map shape or the legacy array shape.
  static Map<String, Set<OutputTag>> decode(Object? json) {
    switch (json) {
      case null:
        return const <String, Set<OutputTag>>{};
      case final List legacy:
        return {
          for (final id in legacy)
            if (id is String) id: <OutputTag>{},
        };
      case final Map map:
        return {
          for (final entry in map.entries)
            entry.key as String: {
              for (final tag in entry.value as List? ?? const <Object?>[])
                if (tag is String) OutputTag.fromValue(tag),
            },
        };
      default:
        throw FormatException(
          'Expected object or array for outputExecutorIds, '
          'got ${json.runtimeType}.',
        );
    }
  }
}

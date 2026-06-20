// Copyright (c) Microsoft. All rights reserved.
//
// Ported from ChatCompletions/Models/ResponseFormat.cs.

/// Specifies the format that the model must output.
///
/// A discriminated union of text, JSON-object, or JSON-schema formats.
class ResponseFormat {
  const ResponseFormat._(this.text, this.jsonSchema, this.jsonObject);

  /// Creates a text response format.
  factory ResponseFormat.fromText() =>
      const ResponseFormat._(TextResponseFormat(), null, null);

  /// Creates a JSON-schema response format.
  factory ResponseFormat.fromJsonSchema(JsonSchemaResponseFormat jsonSchema) =>
      ResponseFormat._(null, jsonSchema, null);

  /// Creates a JSON-object response format.
  factory ResponseFormat.fromJsonObject() =>
      const ResponseFormat._(null, null, JsonObjectResponseFormat());

  /// Parses a [ResponseFormat] from JSON, dispatching on the `type` field.
  factory ResponseFormat.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'text':
        return ResponseFormat.fromText();
      case 'json_schema':
        return ResponseFormat.fromJsonSchema(
          JsonSchemaResponseFormat.fromJson(json),
        );
      case 'json_object':
        return ResponseFormat.fromJsonObject();
      default:
        throw FormatException('Unknown response format type: $type');
    }
  }

  /// The text format, when set.
  final TextResponseFormat? text;

  /// The JSON-schema format, when set.
  final JsonSchemaResponseFormat? jsonSchema;

  /// The JSON-object format, when set.
  final JsonObjectResponseFormat? jsonObject;

  /// Whether this is a text response format.
  bool get isText => text != null;

  /// Whether this is a JSON-schema response format.
  bool get isJsonSchema => jsonSchema != null;

  /// Whether this is a JSON-object response format.
  bool get isJsonObject => jsonObject != null;
}

/// Text response format (the default).
class TextResponseFormat {
  /// Creates a [TextResponseFormat].
  const TextResponseFormat();

  /// The format type, always `text`.
  String get type => 'text';
}

/// JSON-object response format (the older JSON mode).
class JsonObjectResponseFormat {
  /// Creates a [JsonObjectResponseFormat].
  const JsonObjectResponseFormat();

  /// The format type, always `json_object`.
  String get type => 'json_object';
}

/// JSON-schema response format with Structured Outputs.
class JsonSchemaResponseFormat {
  /// Creates a [JsonSchemaResponseFormat].
  const JsonSchemaResponseFormat({required this.jsonSchema});

  /// Parses a [JsonSchemaResponseFormat] from JSON.
  factory JsonSchemaResponseFormat.fromJson(Map<String, dynamic> json) =>
      JsonSchemaResponseFormat(
        jsonSchema: JsonSchemaConfiguration.fromJson(
          json['json_schema'] as Map<String, dynamic>,
        ),
      );

  /// The format type, always `json_schema`.
  String get type => 'json_schema';

  /// The Structured Outputs configuration.
  final JsonSchemaConfiguration jsonSchema;
}

/// Configuration for JSON-Schema Structured Outputs.
class JsonSchemaConfiguration {
  /// Creates a [JsonSchemaConfiguration].
  const JsonSchemaConfiguration({
    required this.name,
    required this.schema,
    this.description,
    this.strict,
  });

  /// Parses a [JsonSchemaConfiguration] from JSON.
  factory JsonSchemaConfiguration.fromJson(Map<String, dynamic> json) =>
      JsonSchemaConfiguration(
        name: json['name'] as String,
        schema: (json['schema'] as Map).cast<String, dynamic>(),
        description: json['description'] as String?,
        strict: json['strict'] as bool?,
      );

  /// The name of the schema.
  final String name;

  /// The JSON-Schema definition.
  final Map<String, dynamic> schema;

  /// A description of the schema.
  final String? description;

  /// Whether to enable strict schema adherence.
  final bool? strict;
}

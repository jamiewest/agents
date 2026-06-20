// Copyright (c) Microsoft. All rights reserved.
//
// Ported from ChatCompletions/Models/Tool.cs.

/// A tool the model may call: a function tool or a custom tool.
abstract class Tool {
  /// Creates a [Tool].
  const Tool();

  /// Parses a [Tool] from JSON, dispatching on the `type` field.
  factory Tool.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'function':
        return FunctionTool(
          function: FunctionDefinition.fromJson(
            json['function'] as Map<String, dynamic>,
          ),
        );
      case 'custom':
        return CustomTool(
          custom: CustomToolProperties.fromJson(
            json['custom'] as Map<String, dynamic>,
          ),
        );
      default:
        throw FormatException('Unknown tool type: $type');
    }
  }

  /// The wire `type` discriminator.
  String get type;
}

/// A function tool.
class FunctionTool extends Tool {
  /// Creates a [FunctionTool].
  const FunctionTool({required this.function});

  /// The function definition.
  final FunctionDefinition function;

  @override
  String get type => 'function';
}

/// Definition of a function the model can call.
class FunctionDefinition {
  /// Creates a [FunctionDefinition].
  const FunctionDefinition({
    required this.name,
    this.description,
    this.parameters,
    this.strict,
  });

  /// Parses a [FunctionDefinition] from JSON.
  factory FunctionDefinition.fromJson(Map<String, dynamic> json) =>
      FunctionDefinition(
        name: json['name'] as String,
        description: json['description'] as String?,
        parameters: (json['parameters'] as Map?)?.cast<String, dynamic>(),
        strict: json['strict'] as bool?,
      );

  /// The name of the function.
  final String name;

  /// A description of what the function does.
  final String? description;

  /// The parameters, as a JSON Schema object.
  final Map<String, dynamic>? parameters;

  /// Whether to enable strict schema adherence.
  final bool? strict;
}

/// A custom tool processing input using a specified format.
class CustomTool extends Tool {
  /// Creates a [CustomTool].
  const CustomTool({required this.custom});

  /// Properties of the custom tool.
  final CustomToolProperties custom;

  @override
  String get type => 'custom';
}

/// Properties of a custom tool.
class CustomToolProperties {
  /// Creates [CustomToolProperties].
  const CustomToolProperties({
    required this.name,
    this.description,
    this.format,
  });

  /// Parses [CustomToolProperties] from JSON.
  factory CustomToolProperties.fromJson(Map<String, dynamic> json) =>
      CustomToolProperties(
        name: json['name'] as String,
        description: json['description'] as String?,
        format: json['format'] == null
            ? null
            : CustomToolFormat.fromJson(json['format'] as Map<String, dynamic>),
      );

  /// The name of the custom tool.
  final String name;

  /// An optional description of the custom tool.
  final String? description;

  /// The input format for the custom tool.
  final CustomToolFormat? format;
}

/// The input format for a custom tool.
class CustomToolFormat {
  /// Creates a [CustomToolFormat].
  const CustomToolFormat({this.type, this.additionalProperties});

  /// Parses a [CustomToolFormat] from JSON.
  factory CustomToolFormat.fromJson(Map<String, dynamic> json) {
    final additional = Map<String, dynamic>.of(json)..remove('type');
    return CustomToolFormat(
      type: json['type'] as String?,
      additionalProperties: additional.isEmpty ? null : additional,
    );
  }

  /// The type of format.
  final String? type;

  /// Additional format properties (schema definition).
  final Map<String, dynamic>? additionalProperties;
}

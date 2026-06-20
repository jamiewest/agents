// Copyright (c) Microsoft. All rights reserved.
//
// Ported from ChatCompletions/Models/ToolChoice.cs.

/// Controls which (if any) tool is called by the model.
///
/// A discriminated union of a mode string, an allowed-tools set, a specific
/// function tool, or a specific custom tool.
class ToolChoice {
  const ToolChoice._(
    this.mode,
    this.allowedTools,
    this.functionTool,
    this.customTool,
  );

  /// Creates a [ToolChoice] from a mode string (`none`, `auto`, `required`).
  factory ToolChoice.fromMode(String mode) =>
      ToolChoice._(mode, null, null, null);

  /// Creates a [ToolChoice] constraining tools to a pre-defined set.
  factory ToolChoice.fromAllowedTools(AllowedToolsChoice allowedTools) =>
      ToolChoice._(null, allowedTools, null, null);

  /// Creates a [ToolChoice] forcing a specific function call.
  factory ToolChoice.fromFunction(FunctionToolChoice functionTool) =>
      ToolChoice._(null, null, functionTool, null);

  /// Creates a [ToolChoice] forcing a specific custom-tool call.
  factory ToolChoice.fromCustom(CustomToolChoice customTool) =>
      ToolChoice._(null, null, null, customTool);

  /// Parses a [ToolChoice] from JSON (string or typed object).
  factory ToolChoice.fromJson(Object? json) {
    if (json is String) {
      return ToolChoice.fromMode(json);
    }
    if (json is Map<String, dynamic>) {
      final type = json['type'] as String?;
      switch (type) {
        case 'allowed_tools':
          return ToolChoice.fromAllowedTools(AllowedToolsChoice.fromJson(json));
        case 'function':
          return ToolChoice.fromFunction(FunctionToolChoice.fromJson(json));
        case 'custom':
          return ToolChoice.fromCustom(CustomToolChoice.fromJson(json));
        default:
          throw FormatException('Unknown tool choice type: $type');
      }
    }
    throw FormatException('Unexpected ToolChoice JSON: $json');
  }

  /// The mode string, when set.
  final String? mode;

  /// The allowed-tools configuration, when set.
  final AllowedToolsChoice? allowedTools;

  /// The function-tool choice, when set.
  final FunctionToolChoice? functionTool;

  /// The custom-tool choice, when set.
  final CustomToolChoice? customTool;

  /// Whether this is a mode string.
  bool get isMode => mode != null;

  /// Whether this is an allowed-tools choice.
  bool get isAllowedTools => allowedTools != null;

  /// Whether this is a function-tool choice.
  bool get isFunctionTool => functionTool != null;

  /// Whether this is a custom-tool choice.
  bool get isCustomTool => customTool != null;
}

/// Constrains the tools available to the model to a pre-defined set.
class AllowedToolsChoice {
  /// Creates an [AllowedToolsChoice].
  const AllowedToolsChoice({required this.allowedTools});

  /// Parses an [AllowedToolsChoice] from JSON.
  factory AllowedToolsChoice.fromJson(Map<String, dynamic> json) =>
      AllowedToolsChoice(
        allowedTools: AllowedToolsConfiguration.fromJson(
          json['allowed_tools'] as Map<String, dynamic>,
        ),
      );

  /// The configuration of allowed tools.
  final AllowedToolsConfiguration allowedTools;
}

/// Configuration for allowed tools.
class AllowedToolsConfiguration {
  /// Creates an [AllowedToolsConfiguration].
  const AllowedToolsConfiguration({required this.mode, required this.tools});

  /// Parses an [AllowedToolsConfiguration] from JSON.
  factory AllowedToolsConfiguration.fromJson(Map<String, dynamic> json) =>
      AllowedToolsConfiguration(
        mode: json['mode'] as String,
        tools: (json['tools'] as List)
            .map((t) => ToolDefinition.fromJson(t as Map<String, dynamic>))
            .toList(),
      );

  /// The allowed-tools mode (`auto` or `required`).
  final String mode;

  /// The tool definitions the model may call.
  final List<ToolDefinition> tools;
}

/// A tool definition in the allowed-tools list.
class ToolDefinition {
  /// Creates a [ToolDefinition].
  const ToolDefinition({required this.type, this.function});

  /// Parses a [ToolDefinition] from JSON.
  factory ToolDefinition.fromJson(Map<String, dynamic> json) => ToolDefinition(
    type: json['type'] as String,
    function: json['function'] == null
        ? null
        : FunctionReference.fromJson(json['function'] as Map<String, dynamic>),
  );

  /// The tool type (`function` or `custom`).
  final String type;

  /// The function details, when [type] is `function`.
  final FunctionReference? function;
}

/// A reference to a function by name.
class FunctionReference {
  /// Creates a [FunctionReference].
  const FunctionReference({required this.name});

  /// Parses a [FunctionReference] from JSON.
  factory FunctionReference.fromJson(Map<String, dynamic> json) =>
      FunctionReference(name: json['name'] as String);

  /// The name of the function.
  final String name;
}

/// Specifies a function tool the model should use.
class FunctionToolChoice {
  /// Creates a [FunctionToolChoice].
  const FunctionToolChoice({required this.function});

  /// Parses a [FunctionToolChoice] from JSON.
  factory FunctionToolChoice.fromJson(Map<String, dynamic> json) =>
      FunctionToolChoice(
        function: FunctionReference.fromJson(
          json['function'] as Map<String, dynamic>,
        ),
      );

  /// The function to call.
  final FunctionReference function;
}

/// Specifies a custom tool the model should use.
class CustomToolChoice {
  /// Creates a [CustomToolChoice].
  const CustomToolChoice({required this.custom});

  /// Parses a [CustomToolChoice] from JSON.
  factory CustomToolChoice.fromJson(Map<String, dynamic> json) =>
      CustomToolChoice(
        custom: CustomToolObject.fromJson(
          json['custom'] as Map<String, dynamic>,
        ),
      );

  /// The custom-tool configuration.
  final CustomToolObject custom;
}

/// A reference to a custom-tool object by name.
class CustomToolObject {
  /// Creates a [CustomToolObject].
  const CustomToolObject({required this.name});

  /// Parses a [CustomToolObject] from JSON.
  factory CustomToolObject.fromJson(Map<String, dynamic> json) =>
      CustomToolObject(name: json['name'] as String);

  /// The name of the custom tool.
  final String name;
}

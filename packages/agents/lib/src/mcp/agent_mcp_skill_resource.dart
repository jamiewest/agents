import 'dart:convert';

import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:extensions/system.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp;

import '../ai/skills/agent_skill_resource.dart';

/// A skill resource backed by content returned from an MCP server.
class AgentMcpSkillResource extends AgentSkillResource {
  /// Creates an MCP skill resource from a pre-fetched resource result.
  AgentMcpSkillResource(super.name, this.result, {super.description});

  /// The MCP resource result that contains this resource's content.
  final mcp.ReadResourceResult result;

  @override
  Future<Object?> read({
    ServiceProvider? serviceProvider,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();

    for (final content in result.contents) {
      if (content is mcp.BlobResourceContents) {
        return DataContent(
          base64Decode(content.blob),
          mediaType: content.mimeType ?? 'application/octet-stream',
          name: name,
        );
      }
    }

    final text = result.contents
        .whereType<mcp.TextResourceContents>()
        .map((content) => content.text)
        .join('\n');
    return text.isEmpty ? null : text;
  }
}

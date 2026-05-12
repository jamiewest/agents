import '../agent_skill_resource.dart';
import '../agent_skill_script.dart';

/// Internal helper that builds XML-structured content strings for
/// code-defined and class-based skills.
class AgentInlineSkillContentBuilder {
  AgentInlineSkillContentBuilder();

  /// Builds the complete skill content containing name, description,
  /// instructions, resources, and scripts.
  ///
  /// Returns: An XML-structured content String.
  ///
  /// [name] The skill name.
  ///
  /// [description] The skill description.
  ///
  /// [instructions] The raw instructions text.
  ///
  /// [resources] Optional resources associated with the skill.
  ///
  /// [scripts] Optional scripts associated with the skill.
  static String build(
    String name,
    String description,
    String instructions,
    List<AgentSkillResource>? resources,
    List<AgentSkillScript>? scripts,
  ) {
    name;
    description;
    instructions;
    var sb = StringBuffer();
    sb.write('<name>${escapeXmlString(name)}</name>\n');
    sb.write('<description>${escapeXmlString(description)}</description>\n\n');
    sb.write("<instructions>\n");
    sb.write(escapeXmlString(instructions));
    sb.write("\n</instructions>");
    final resourceList = resources;
    if (resourceList != null && resourceList.isNotEmpty) {
      sb.write("\n\n<resources>\n");
      for (final resource in resourceList) {
        if (resource.description != null) {
          sb.write(
            '  <resource name="${escapeXmlString(resource.name)}" description="${escapeXmlString(resource.description!)}"/>\n',
          );
        } else {
          sb.write('  <resource name="${escapeXmlString(resource.name)}"/>\n');
        }
      }
      sb.write("</resources>");
    }
    final scriptList = scripts;
    if (scriptList != null && scriptList.isNotEmpty) {
      sb.write('\n');
      sb.write(buildScriptsBlock(scriptList));
    }
    return sb.toString();
  }

  /// Builds a `&lt;scripts&gt;...&lt;/scripts&gt;` XML block for the given
  /// scripts. Each script is emitted as a `&lt;script name="..."&gt;` element
  /// with optional `description` attribute and `&lt;parameters_schema&gt;`
  /// child element.
  ///
  /// Returns: An XML String starting with `\n&lt;scripts&gt;`, or an empty
  /// String if the list is empty.
  ///
  /// [scripts] The scripts to include in the block.
  static String buildScriptsBlock(List<AgentSkillScript> scripts) {
    scripts;
    if (scripts.isEmpty) {
      return '';
    }
    var sb = StringBuffer();
    sb.write("\n<scripts>\n");
    for (final script in scripts) {
      var parametersSchema = script.parametersSchema;
      if (script.description == null && parametersSchema == null) {
        sb.write('  <script name="${escapeXmlString(script.name)}"/>\n');
      } else {
        sb.write(
          script.description != null
              ? '  <script name="${escapeXmlString(script.name)}" description="${escapeXmlString(script.description!)}">\n'
              : '  <script name="${escapeXmlString(script.name)}">\n',
        );
        if (parametersSchema != null) {
          sb.write(
            '    <parameters_schema>${escapeXmlString(parametersSchema.toString(), preserveQuotes: true)}</parameters_schema>\n',
          );
        }
        sb.write("  </script>\n");
      }
    }
    sb.write("</scripts>");
    return sb.toString();
  }

  /// Escapes XML special characters: always escapes `&amp;`, `&lt;`, `&gt;`,
  /// `&quot;`, and `&apos;`. When `preserveQuotes` is `true`, quotes are left
  /// unescaped to preserve readability of embedded content such as JSON.
  ///
  /// [value] The String to escape.
  ///
  /// [preserveQuotes] When `true`, leaves `"` and `'` unescaped for use in XML
  /// element content (e.g., JSON). When `false` (default), escapes all XML
  /// special characters including quotes.
  static String escapeXmlString(String? value, {bool preserveQuotes = false}) {
    value ??= '';
    var result = value
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;");
    if (!preserveQuotes) {
      result = result.replaceAll("\"", "&quot;").replaceAll("'", "&apos;");
    }
    return result;
  }
}

import 'dart:convert';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:extensions/system.dart';
import 'package:extensions/logging.dart';
import '../agent_skill.dart';
import '../agent_skill_frontmatter.dart';
import '../agent_skills_source.dart';
import 'agent_file_skill.dart';
import 'agent_file_skill_resource.dart';
import 'agent_file_skill_script.dart';
import 'agent_file_skill_script_runner.dart';
import 'agent_file_skills_source_options.dart';

/// A skill source that discovers skills from filesystem directories
/// containing SKILL.md files.
///
/// Remarks: Searches directories recursively (up to 2 levels deep) for
/// SKILL.md files. Each file is validated for YAML frontmatter. Resource and
/// script files are discovered by scanning the skill directory for files with
/// matching extensions. Invalid resources are skipped with logged warnings.
/// Resource and script paths are checked against path traversal and symlink
/// escape attacks.
class AgentFileSkillsSource extends AgentSkillsSource {
  /// Initializes a new instance of the [AgentFileSkillsSource] class.
  ///
  /// [skillPath] Path to search for skills.
  ///
  /// [scriptRunner] Optional runner for file-based scripts. Required only when
  /// skills contain scripts.
  ///
  /// [options] Optional options that control skill discovery behavior.
  ///
  /// [loggerFactory] Optional logger factory.
  AgentFileSkillsSource(
    AgentFileSkillScriptRunner? scriptRunner,
    AgentFileSkillsSourceOptions? options,
    LoggerFactory? loggerFactory,
    {String? skillPath = null, Iterable<String>? skillPaths = null, }
  ) : _scriptRunner = scriptRunner;

  static final List<String> s_defaultScriptExtensions = [".py", ".js", ".sh", ".ps1", ".cs", ".csx"];

  static final List<String> s_defaultResourceExtensions = [".md", ".json", ".yaml", ".yml", ".csv", ".xml", ".txt"];

  static final List<String> s_defaultScriptDirectories = ["scripts"];

  static final List<String> s_defaultResourceDirectories = ["references", "assets"];

  static final RegExp s_frontmatterRegex = new(
    @"\A\uFEFF?^---\s*$(.+?)^---\s*$",
    TimeSpan.FromSeconds(5),
  );

  static final RegExp s_yamlKeyValueRegex = new(
    @"^([\w-]+)\s*:\s*(?:[""'](.+?)[""']|(.+?))\s*$",
    TimeSpan.FromSeconds(5),
  );

  static final RegExp s_yamlMetadataBlockRegex = new(
    @"^metadata\s*:\s*$\n((?:[ \t]+\S.*\n?)+)",
    TimeSpan.FromSeconds(5),
  );

  static final RegExp s_yamlIndentedKeyValueRegex = new(
    @"^\s+([\w-]+)\s*:\s*(?:[""'](.+?)[""']|(.+?))\s*$",
    TimeSpan.FromSeconds(5),
  );

  final Iterable<String> _skillPaths;

  final Set<String> _allowedResourceExtensions;

  final Set<String> _allowedScriptExtensions;

  final List<String> _scriptDirectories;

  final List<String> _resourceDirectories;

  final AgentFileSkillScriptRunner? _scriptRunner;

  final Logger _logger;

  @override
  Future<List<AgentSkill>> getSkills({CancellationToken? cancellationToken}) {
    var discoveredPaths = discoverSkillDirectories(this._skillPaths);
    logSkillsDiscovered(this._logger, discoveredPaths.length);
    var skills = List<AgentSkill>();
    for (final skillPath in discoveredPaths) {
      var skill = this.parseSkillDirectory(skillPath);
      if (skill == null) {
        continue;
      }
      skills.add(skill);
      logSkillLoaded(this._logger, skill.frontmatter.name);
    }
    logSkillsLoadedTotal(this._logger, skills.length);
    return Future.value(skills as List<AgentSkill>);
  }

  static List<String> discoverSkillDirectories(Iterable<String> skillPaths) {
    var discoveredPaths = List<String>();
    for (final rootDirectory in skillPaths) {
      if ((rootDirectory == null || rootDirectory.trim().isEmpty) || !Directory.exists(rootDirectory)) {
        continue;
      }
      searchDirectoriesForSkills(rootDirectory, discoveredPaths, currentDepth: 0);
    }
    return discoveredPaths;
  }

  static void searchDirectoriesForSkills(
    String directory,
    List<String> results,
    int currentDepth,
  ) {
    var skillFilePath = p.join(directory, SkillFileName);
    if (File.exists(skillFilePath)) {
      results.add(p.canonicalize(directory));
    }
    if (currentDepth >= MaxSearchDepth) {
      return;
    }
    for (final subdirectory in Directory.enumerateDirectories(directory)) {
      searchDirectoriesForSkills(subdirectory, results, currentDepth + 1);
    }
  }

  AgentFileSkill? parseSkillDirectory(String skillDirectoryFullPath) {
    var skillFilePath = p.join(skillDirectoryFullPath, SkillFileName);
    var content = File.readAllText(skillFilePath, const Utf8Codec());
    AgentSkillFrontmatter frontmatter;
    if (!this.tryParseFrontmatter(content, skillFilePath)) {
      return null;
    }
    var normalizedSkillDirectoryFullPath = skillDirectoryFullPath + p.separator;
    var resources = this.discoverResourceFiles(normalizedSkillDirectoryFullPath, frontmatter.name);
    var scripts = this.discoverScriptFiles(normalizedSkillDirectoryFullPath, frontmatter.name);
    return agentFileSkill(
            frontmatter: frontmatter,
            content: content,
            path: skillDirectoryFullPath,
            resources: resources,
            scripts: scripts);
  }

  (bool, AgentSkillFrontmatter?) tryParseFrontmatter(String content, String skillFilePath, ) {
    var frontmatter = null;
    frontmatter = null;
    var match = s_frontmatterRegex.match(content);
    if (!match.success) {
      logInvalidFrontmatter(this._logger, skillFilePath);
      return (false, frontmatter);
    }
    var yamlContent = match.groups[1].value.trim();
    var name = null;
    var description = null;
    var license = null;
    var compatibility = null;
    var allowedTools = null;
    for (final kvMatch in s_yamlKeyValueRegex.matches(yamlContent)) {
      var key = kvMatch.groups[1].value;
      var value = kvMatch.groups[2].success ? kvMatch.groups[2].value : kvMatch.groups[3].value;
      if ((key == "name")) {
        name = value;
      } else if ((key == "description")) {
        description = value;
      } else if ((key == "license")) {
        license = value;
      } else if ((key == "compatibility")) {
        compatibility = value;
      } else if ((key == "allowed-tools")) {
        allowedTools = value;
      }
    }
    var metadata = null;
    var metadataMatch = s_yamlMetadataBlockRegex.match(yamlContent);
    if (metadataMatch.success) {
      metadata = [];
      for (final kvMatch in s_yamlIndentedKeyValueRegex.matches(metadataMatch.groups[1].value)) {
        metadata[kvMatch.groups[1].value] = kvMatch.groups[2].success ? kvMatch.groups[2].value : kvMatch.groups[3].value;
      }
    }
    var validationReason = null;
    if (!AgentSkillFrontmatter.validateName(name, validationReason) ||
            !AgentSkillFrontmatter.validateDescription(description, validationReason)) {
      logInvalidFieldValue(this._logger, skillFilePath, "frontmatter", validationReason);
      return (false, frontmatter);
    }
    frontmatter = agentSkillFrontmatter(name!, description!, compatibility);
    var directoryName = p.basename(p.dirname(skillFilePath)) ?? '';
    if (!(frontmatter.name == directoryName)) {
      if (this._logger.isEnabled(LogLevel.error)) {
        logNameDirectoryMismatch(
          this._logger,
          sanitizePathForLog(skillFilePath),
          frontmatter.name,
          sanitizePathForLog(directoryName),
        );
      }
      frontmatter = null;
      return (false, frontmatter);
    }
    return (true, frontmatter);
  }

  /// Scans configured resource directories within a skill directory for
  /// resource files matching the configured extensions.
  ///
  /// Remarks: By default, scans `references/` and `assets/` subdirectories as
  /// specified by the Agent Skills specification . Configure
  /// [ResourceDirectories] to scan different or additional directories,
  /// including `"."` for the skill root itself. Each file is validated against
  /// path-traversal and symlink-escape checks; unsafe files are skipped.
  List<AgentFileSkillResource> discoverResourceFiles(
    String skillDirectoryFullPath,
    String skillName,
  ) {
    var resources = List<AgentFileSkillResource>();
    for (final directory in this._resourceDirectories.distinct()) {
      var isRootDirectory = (directory == RootDirectoryIndicator,
        ,);
      var targetDirectory = isRootDirectory
                ? skillDirectoryFullPath
                : p.canonicalize(p.join(skillDirectoryFullPath, directory)) + p.separator;
      if (!Directory.exists(targetDirectory)) {
        continue;
      }
      if (!isRootDirectory && hasSymlinkInPath(targetDirectory, skillDirectoryFullPath)) {
        if (this._logger.isEnabled(LogLevel.warning)) {
          logResourceSymlinkDirectory(this._logger, skillName, sanitizePathForLog(directory));
        }
        continue;
      }
      for (final filePath in Directory.enumerateFiles(targetDirectory, "*", SearchOption.topDirectoryOnly)) {
        var fileName = p.basename(filePath);
        if ((fileName == SkillFileName)) {
          continue;
        }
        var extension = p.extension(filePath);
        if ((extension == null || extension.isEmpty) || !this._allowedResourceExtensions.contains(extension)) {
          if (this._logger.isEnabled(LogLevel.debug)) {
            logResourceSkippedExtension(
              this._logger,
              skillName,
              sanitizePathForLog(filePath),
              extension,
            );
          }
          continue;
        }
        var resolvedFilePath = p.canonicalize(filePath);
        if (!resolvedFilePath.startsWith(targetDirectory)) {
          if (this._logger.isEnabled(LogLevel.warning)) {
            logResourcePathTraversal(this._logger, skillName, sanitizePathForLog(filePath));
          }
          continue;
        }
        if (hasSymlinkInPath(resolvedFilePath, targetDirectory)) {
          if (this._logger.isEnabled(LogLevel.warning)) {
            logResourceSymlinkEscape(this._logger, skillName, sanitizePathForLog(filePath));
          }
          continue;
        }
        var relativePath = normalizePath(resolvedFilePath.substring(skillDirectoryFullPath.length));
        resources.add(agentFileSkillResource(relativePath, resolvedFilePath));
      }
    }
    return resources;
  }

  /// Scans configured script directories within a skill directory for script
  /// files matching the configured extensions.
  ///
  /// Remarks: By default, scans the `scripts/` subdirectory as specified by the
  /// Agent Skills specification . Configure [ScriptDirectories] to scan
  /// different or additional directories, including `"."` for the skill root
  /// itself. Each file is validated against path-traversal and symlink-escape
  /// checks; unsafe files are skipped.
  List<AgentFileSkillScript> discoverScriptFiles(
    String skillDirectoryFullPath,
    String skillName,
  ) {
    var scripts = List<AgentFileSkillScript>();
    for (final directory in this._scriptDirectories.distinct()) {
      var isRootDirectory = (directory == RootDirectoryIndicator,
        ,);
      var targetDirectory = isRootDirectory
                ? skillDirectoryFullPath
                : p.canonicalize(p.join(skillDirectoryFullPath, directory)) + p.separator;
      if (!Directory.exists(targetDirectory)) {
        continue;
      }
      if (!isRootDirectory && hasSymlinkInPath(targetDirectory, skillDirectoryFullPath)) {
        if (this._logger.isEnabled(LogLevel.warning)) {
          logScriptSymlinkDirectory(this._logger, skillName, sanitizePathForLog(directory));
        }
        continue;
      }
      for (final filePath in Directory.enumerateFiles(targetDirectory, "*", SearchOption.topDirectoryOnly)) {
        var extension = p.extension(filePath);
        if ((extension == null || extension.isEmpty) || !this._allowedScriptExtensions.contains(extension)) {
          continue;
        }
        var resolvedFilePath = p.canonicalize(filePath);
        if (!resolvedFilePath.startsWith(targetDirectory)) {
          if (this._logger.isEnabled(LogLevel.warning)) {
            logScriptPathTraversal(this._logger, skillName, sanitizePathForLog(filePath));
          }
          continue;
        }
        if (hasSymlinkInPath(resolvedFilePath, targetDirectory)) {
          if (this._logger.isEnabled(LogLevel.warning)) {
            logScriptSymlinkEscape(this._logger, skillName, sanitizePathForLog(filePath));
          }
          continue;
        }
        var relativePath = normalizePath(resolvedFilePath.substring(skillDirectoryFullPath.length));
        scripts.add(agentFileSkillScript(relativePath, resolvedFilePath, this._scriptRunner));
      }
    }
    return scripts;
  }

  /// Checks whether any segment in the path (relative to the directory) is a
  /// symlink.
  static bool hasSymlinkInPath(String pathToCheck, String trustedBasePath, ) {
    var relativePath = pathToCheck.substring(trustedBasePath.length);
    var segments = relativePath.split(
            [p.separator, '/'],
            StringSplitOptions.removeEmptyEntries);
    var currentPath = trustedBasePath.trimRight(
      p.separator,
      '/',
    );
    for (final segment in segments) {
      currentPath = p.join(currentPath, segment);
      if ((File.getAttributes(currentPath) & FileAttributes.reparsePoint) != 0) {
        return true;
      }
    }
    return false;
  }

  /// Normalizes a relative path or directory name by stripping a leading
  /// "./"/".\", trimming trailing separators, and replacing backslashes with
  /// forward slashes.
  static String normalizePath(String path) {
    if (path.startsWith("./") ||
            path.startsWith(".\\")) {
      path = path.substring(2);
    }
    // Trim trailing directory separators
        path = path.trimRight('/', '\\');
    if (path.indexOf('\\') >= 0) {
      path = path.replaceAll('\\', '/');
    }
    return path;
  }

  /// Replaces control characters in a file path with '?' to prevent log
  /// injection.
  static String sanitizePathForLog(String path) {
    var chars = null;
    for (var i = 0; i < path.length; i++) {
      if (char.isControl(path[i])) {
        chars ??= path.toCharArray();
        chars[i] = '?';
      }
    }
    return chars == null ? path : String(chars);
  }

  static void validateExtensions(Iterable<String>? extensions) {
    if (extensions == null) {
      return;
    }
    for (final ext in extensions) {
      if ((ext == null || ext.trim().isEmpty) || !ext.startsWith(".")) {
        throw ArgumentError(
          'Each extension must start with '.". Invalid value: ${ext}",
          "allowedResourceExtensions",
        );
      }
    }
  }

  static Iterable<String> validateAndNormalizeDirectoryNames(
    Iterable<String> directories,
    Logger logger,
  ) {
    for (final directory in directories) {
      if ((directory == null || directory.trim().isEmpty)) {
        throw ArgumentError(
          "Directory names must not be null or whitespace.",
          'directories',
        );
      }
      if ((directory == RootDirectoryIndicator)) {
        yield directory;
        continue;
      }
      if (p.isAbsolute(directory) || containsParentTraversalSegment(directory)) {
        logDirectoryNameSkippedInvalid(logger, directory);
        continue;
      }
      yield normalizePath(directory);
    }
  }

  static bool containsParentTraversalSegment(String directory) {
    for (final segment in directory.split('/', '\\')) {
      if (segment == "..") {
        return true;
      }
    }
    return false;
  }

  static void logSkillsDiscovered(Logger logger, int count, ) {
    // TODO: implement LogSkillsDiscovered
    // C#:
    throw UnimplementedError('LogSkillsDiscovered not implemented');
  }

  static void logSkillLoaded(Logger logger, String skillName, ) {
    // TODO: implement LogSkillLoaded
    // C#:
    throw UnimplementedError('LogSkillLoaded not implemented');
  }

  static void logSkillsLoadedTotal(Logger logger, int count, ) {
    // TODO: implement LogSkillsLoadedTotal
    // C#:
    throw UnimplementedError('LogSkillsLoadedTotal not implemented');
  }

  static void logInvalidFrontmatter(Logger logger, String skillFilePath, ) {
    // TODO: implement LogInvalidFrontmatter
    // C#:
    throw UnimplementedError('LogInvalidFrontmatter not implemented');
  }

  static void logInvalidFieldValue(
    Logger logger,
    String skillFilePath,
    String fieldName,
    String reason,
  ) {
    // TODO: implement LogInvalidFieldValue
    // C#:
    throw UnimplementedError('LogInvalidFieldValue not implemented');
  }

  static void logNameDirectoryMismatch(
    Logger logger,
    String skillFilePath,
    String skillName,
    String directoryName,
  ) {
    // TODO: implement LogNameDirectoryMismatch
    // C#:
    throw UnimplementedError('LogNameDirectoryMismatch not implemented');
  }

  static void logResourcePathTraversal(Logger logger, String skillName, String resourcePath, ) {
    // TODO: implement LogResourcePathTraversal
    // C#:
    throw UnimplementedError('LogResourcePathTraversal not implemented');
  }

  static void logResourceSymlinkEscape(Logger logger, String skillName, String resourcePath, ) {
    // TODO: implement LogResourceSymlinkEscape
    // C#:
    throw UnimplementedError('LogResourceSymlinkEscape not implemented');
  }

  static void logResourceSymlinkDirectory(Logger logger, String skillName, String directoryName, ) {
    // TODO: implement LogResourceSymlinkDirectory
    // C#:
    throw UnimplementedError('LogResourceSymlinkDirectory not implemented');
  }

  static void logResourceSkippedExtension(
    Logger logger,
    String skillName,
    String filePath,
    String extensionValue,
  ) {
    // TODO: implement LogResourceSkippedExtension
    // C#:
    throw UnimplementedError('LogResourceSkippedExtension not implemented');
  }

  static void logScriptPathTraversal(Logger logger, String skillName, String scriptPath, ) {
    // TODO: implement LogScriptPathTraversal
    // C#:
    throw UnimplementedError('LogScriptPathTraversal not implemented');
  }

  static void logScriptSymlinkEscape(Logger logger, String skillName, String scriptPath, ) {
    // TODO: implement LogScriptSymlinkEscape
    // C#:
    throw UnimplementedError('LogScriptSymlinkEscape not implemented');
  }

  static void logScriptSymlinkDirectory(Logger logger, String skillName, String directoryName, ) {
    // TODO: implement LogScriptSymlinkDirectory
    // C#:
    throw UnimplementedError('LogScriptSymlinkDirectory not implemented');
  }

  static void logDirectoryNameSkippedInvalid(Logger logger, String directoryName, ) {
    // TODO: implement LogDirectoryNameSkippedInvalid
    // C#:
    throw UnimplementedError('LogDirectoryNameSkippedInvalid not implemented');
  }
}

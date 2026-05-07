import 'dart:convert';
import 'dart:io';

import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';
import 'package:path/path.dart' as p;

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
class AgentFileSkillsSource extends AgentSkillsSource {
  AgentFileSkillsSource(
    Iterable<String> skillPaths, {
    AgentFileSkillScriptRunner? scriptRunner,
    AgentFileSkillsSourceOptions? options,
    LoggerFactory? loggerFactory,
  }) : _skillPaths = List<String>.of(skillPaths),
       _scriptRunner = scriptRunner,
       _logger = (loggerFactory ?? NullLoggerFactory.instance).createLogger(
         'AgentFileSkillsSource',
       ) {
    validateExtensions(options?.allowedResourceExtensions);
    validateExtensions(options?.allowedScriptExtensions);
    _allowedResourceExtensions =
        (options?.allowedResourceExtensions ?? defaultResourceExtensions)
            .map((extension) => extension.toLowerCase())
            .toSet();
    _allowedScriptExtensions =
        (options?.allowedScriptExtensions ?? defaultScriptExtensions)
            .map((extension) => extension.toLowerCase())
            .toSet();
    _scriptDirectories = validateAndNormalizeDirectoryNames(
      options?.scriptDirectories ?? defaultScriptDirectories,
      _logger,
    ).toList();
    _resourceDirectories = validateAndNormalizeDirectoryNames(
      options?.resourceDirectories ?? defaultResourceDirectories,
      _logger,
    ).toList();
  }

  static const String skillFileName = 'SKILL.md';
  static const int maxSearchDepth = 2;
  static const String rootDirectoryIndicator = '.';
  static const List<String> defaultScriptExtensions = [
    '.py',
    '.js',
    '.sh',
    '.ps1',
    '.cs',
    '.csx',
  ];
  static const List<String> defaultResourceExtensions = [
    '.md',
    '.json',
    '.yaml',
    '.yml',
    '.csv',
    '.xml',
    '.txt',
  ];
  static const List<String> defaultScriptDirectories = ['scripts'];
  static const List<String> defaultResourceDirectories = [
    'references',
    'assets',
  ];

  final List<String> _skillPaths;
  late final Set<String> _allowedResourceExtensions;
  late final Set<String> _allowedScriptExtensions;
  late final List<String> _scriptDirectories;
  late final List<String> _resourceDirectories;
  final AgentFileSkillScriptRunner? _scriptRunner;
  final Logger _logger;

  @override
  Future<List<AgentSkill>> getSkills({
    CancellationToken? cancellationToken,
  }) async {
    final discoveredPaths = discoverSkillDirectories(_skillPaths);
    logSkillsDiscovered(_logger, discoveredPaths.length);
    final skills = <AgentSkill>[];
    for (final skillPath in discoveredPaths) {
      final skill = parseSkillDirectory(skillPath);
      if (skill != null) {
        skills.add(skill);
        logSkillLoaded(_logger, skill.frontmatter.name);
      }
    }
    logSkillsLoadedTotal(_logger, skills.length);
    return skills;
  }

  static List<String> discoverSkillDirectories(Iterable<String> skillPaths) {
    final discoveredPaths = <String>[];
    for (final rootDirectory in skillPaths) {
      if (rootDirectory.trim().isEmpty ||
          !Directory(rootDirectory).existsSync()) {
        continue;
      }
      searchDirectoriesForSkills(
        p.canonicalize(rootDirectory),
        discoveredPaths,
        currentDepth: 0,
      );
    }
    return discoveredPaths;
  }

  static void searchDirectoriesForSkills(
    String directory,
    List<String> results, {
    required int currentDepth,
  }) {
    final skillFilePath = p.join(directory, skillFileName);
    if (File(skillFilePath).existsSync()) {
      results.add(p.canonicalize(directory));
    }
    if (currentDepth >= maxSearchDepth) {
      return;
    }
    for (final entry in Directory(directory).listSync(followLinks: false)) {
      if (entry is Directory) {
        searchDirectoriesForSkills(
          entry.path,
          results,
          currentDepth: currentDepth + 1,
        );
      }
    }
  }

  AgentFileSkill? parseSkillDirectory(String skillDirectoryFullPath) {
    final skillFilePath = p.join(skillDirectoryFullPath, skillFileName);
    final content = File(skillFilePath).readAsStringSync(encoding: utf8);
    final (valid, frontmatter) = tryParseFrontmatter(content, skillFilePath);
    if (!valid || frontmatter == null) {
      return null;
    }

    final normalizedSkillDirectoryFullPath =
        '${p.canonicalize(skillDirectoryFullPath)}${p.separator}';
    final resources = discoverResourceFiles(
      normalizedSkillDirectoryFullPath,
      frontmatter.name,
    );
    final scripts = discoverScriptFiles(
      normalizedSkillDirectoryFullPath,
      frontmatter.name,
    );
    return AgentFileSkill(
      frontmatter,
      content,
      skillDirectoryFullPath,
      resources: resources,
      scripts: scripts,
    );
  }

  (bool, AgentSkillFrontmatter?) tryParseFrontmatter(
    String content,
    String skillFilePath,
  ) {
    final match = RegExp(
      r'^\uFEFF?---\s*\r?\n([\s\S]*?)\r?\n---\s*(?:\r?\n|$)',
    ).firstMatch(content);
    if (match == null) {
      logInvalidFrontmatter(_logger, skillFilePath);
      return (false, null);
    }

    final yamlContent = match.group(1) ?? '';
    final values = _parseYamlFrontmatter(yamlContent);
    final name = values['name'];
    final description = values['description'];
    final compatibility = values['compatibility'];

    final (validName, nameReason) = AgentSkillFrontmatter.validateName(name);
    if (!validName) {
      logInvalidFieldValue(_logger, skillFilePath, 'name', nameReason ?? '');
      return (false, null);
    }
    final (validDescription, descriptionReason) =
        AgentSkillFrontmatter.validateDescription(description);
    if (!validDescription) {
      logInvalidFieldValue(
        _logger,
        skillFilePath,
        'description',
        descriptionReason ?? '',
      );
      return (false, null);
    }

    final directoryName = p.basename(p.dirname(skillFilePath));
    if (name != directoryName) {
      logNameDirectoryMismatch(_logger, skillFilePath, name!, directoryName);
      return (false, null);
    }

    return (
      true,
      AgentSkillFrontmatter(
        name!,
        description!,
        compatibility: compatibility,
        license: values['license'],
        allowedTools: values['allowed-tools'],
        metadata: _parseMetadataBlock(yamlContent),
      ),
    );
  }

  List<AgentFileSkillResource> discoverResourceFiles(
    String skillDirectoryFullPath,
    String skillName,
  ) {
    final resources = <AgentFileSkillResource>[];
    for (final directory in _resourceDirectories.toSet()) {
      final isRootDirectory = directory == rootDirectoryIndicator;
      final targetDirectory = isRootDirectory
          ? skillDirectoryFullPath
          : '${p.canonicalize(p.join(skillDirectoryFullPath, directory))}${p.separator}';
      if (!Directory(targetDirectory).existsSync()) {
        continue;
      }
      for (final entry in Directory(
        targetDirectory,
      ).listSync(followLinks: false)) {
        if (entry is! File) {
          continue;
        }
        final filePath = entry.path;
        final fileName = p.basename(filePath);
        if (fileName == skillFileName) {
          continue;
        }
        final extension = p.extension(filePath).toLowerCase();
        if (extension.isEmpty ||
            !_allowedResourceExtensions.contains(extension)) {
          logResourceSkippedExtension(_logger, skillName, filePath, extension);
          continue;
        }
        final resolvedFilePath = p.canonicalize(filePath);
        if (!resolvedFilePath.startsWith(targetDirectory)) {
          logResourcePathTraversal(_logger, skillName, filePath);
          continue;
        }
        final relativePath = normalizePath(
          resolvedFilePath.substring(skillDirectoryFullPath.length),
        );
        resources.add(AgentFileSkillResource(relativePath, resolvedFilePath));
      }
    }
    return resources;
  }

  List<AgentFileSkillScript> discoverScriptFiles(
    String skillDirectoryFullPath,
    String skillName,
  ) {
    final scripts = <AgentFileSkillScript>[];
    for (final directory in _scriptDirectories.toSet()) {
      final isRootDirectory = directory == rootDirectoryIndicator;
      final targetDirectory = isRootDirectory
          ? skillDirectoryFullPath
          : '${p.canonicalize(p.join(skillDirectoryFullPath, directory))}${p.separator}';
      if (!Directory(targetDirectory).existsSync()) {
        continue;
      }
      for (final entry in Directory(
        targetDirectory,
      ).listSync(followLinks: false)) {
        if (entry is! File) {
          continue;
        }
        final filePath = entry.path;
        final extension = p.extension(filePath).toLowerCase();
        if (extension.isEmpty ||
            !_allowedScriptExtensions.contains(extension)) {
          continue;
        }
        final resolvedFilePath = p.canonicalize(filePath);
        if (!resolvedFilePath.startsWith(targetDirectory)) {
          logScriptPathTraversal(_logger, skillName, filePath);
          continue;
        }
        final relativePath = normalizePath(
          resolvedFilePath.substring(skillDirectoryFullPath.length),
        );
        scripts.add(
          AgentFileSkillScript(
            relativePath,
            resolvedFilePath,
            runner: _scriptRunner,
          ),
        );
      }
    }
    return scripts;
  }

  static Map<String, String> _parseYamlFrontmatter(String yamlContent) {
    final values = <String, String>{};
    final lineRegex = RegExp(
      r'''^([\w-]+)\s*:\s*(?:"([^"]*)"|'([^']*)'|(.+?))\s*$''',
    );
    for (final line in const LineSplitter().convert(yamlContent)) {
      final match = lineRegex.firstMatch(line);
      if (match == null) {
        continue;
      }
      values[match.group(1)!] =
          match.group(2) ?? match.group(3) ?? match.group(4)?.trim() ?? '';
    }
    return values;
  }

  static AdditionalPropertiesDictionary? _parseMetadataBlock(
    String yamlContent,
  ) {
    final lines = const LineSplitter().convert(yamlContent);
    final metadata = <String, Object?>{};
    var inMetadata = false;
    final valueRegex = RegExp(
      r'''^\s+([\w-]+)\s*:\s*(?:"([^"]*)"|'([^']*)'|(.+?))\s*$''',
    );
    for (final line in lines) {
      if (line.trim() == 'metadata:') {
        inMetadata = true;
        continue;
      }
      if (!inMetadata) {
        continue;
      }
      if (line.trim().isEmpty) {
        continue;
      }
      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        break;
      }
      final match = valueRegex.firstMatch(line);
      if (match != null) {
        metadata[match.group(1)!] =
            match.group(2) ?? match.group(3) ?? match.group(4)?.trim() ?? '';
      }
    }
    return metadata.isEmpty ? null : metadata;
  }

  static String normalizePath(String path) {
    var result = path;
    if (result.startsWith('./') || result.startsWith('.\\')) {
      result = result.substring(2);
    }
    result = result.replaceAll('\\', '/');
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static String sanitizePathForLog(String path) {
    return path.runes
        .map((rune) => rune < 0x20 || rune == 0x7f ? 0x3f : rune)
        .map(String.fromCharCode)
        .join();
  }

  static void validateExtensions(Iterable<String>? extensions) {
    if (extensions == null) {
      return;
    }
    for (final extension in extensions) {
      if (extension.trim().isEmpty || !extension.startsWith('.')) {
        throw ArgumentError.value(
          extension,
          'extensions',
          'Each extension must start with ".".',
        );
      }
    }
  }

  static Iterable<String> validateAndNormalizeDirectoryNames(
    Iterable<String> directories,
    Logger logger,
  ) sync* {
    for (final directory in directories) {
      if (directory.trim().isEmpty) {
        throw ArgumentError.value(
          directory,
          'directories',
          'Directory names must not be null or whitespace.',
        );
      }
      if (directory == rootDirectoryIndicator) {
        yield directory;
        continue;
      }
      if (p.isAbsolute(directory) ||
          containsParentTraversalSegment(directory)) {
        logDirectoryNameSkippedInvalid(logger, directory);
        continue;
      }
      yield normalizePath(directory);
    }
  }

  static bool containsParentTraversalSegment(String directory) {
    return directory
        .replaceAll('\\', '/')
        .split('/')
        .any((segment) => segment == '..');
  }

  static void logSkillsDiscovered(Logger logger, int count) {
    if (logger.isEnabled(LogLevel.debug)) {
      logger.logDebug('Discovered $count skill directories.');
    }
  }

  static void logSkillLoaded(Logger logger, String skillName) {
    if (logger.isEnabled(LogLevel.debug)) {
      logger.logDebug('Loaded skill $skillName.');
    }
  }

  static void logSkillsLoadedTotal(Logger logger, int count) {
    if (logger.isEnabled(LogLevel.debug)) {
      logger.logDebug('Loaded $count skills.');
    }
  }

  static void logInvalidFrontmatter(Logger logger, String skillFilePath) {
    if (logger.isEnabled(LogLevel.warning)) {
      logger.logWarning(
        'Invalid skill frontmatter: ${sanitizePathForLog(skillFilePath)}.',
      );
    }
  }

  static void logInvalidFieldValue(
    Logger logger,
    String skillFilePath,
    String fieldName,
    String reason,
  ) {
    if (logger.isEnabled(LogLevel.warning)) {
      logger.logWarning(
        'Invalid skill $fieldName in ${sanitizePathForLog(skillFilePath)}: $reason',
      );
    }
  }

  static void logNameDirectoryMismatch(
    Logger logger,
    String skillFilePath,
    String skillName,
    String directoryName,
  ) {
    if (logger.isEnabled(LogLevel.warning)) {
      logger.logWarning(
        'Skill name $skillName does not match directory $directoryName in ${sanitizePathForLog(skillFilePath)}.',
      );
    }
  }

  static void logResourcePathTraversal(
    Logger logger,
    String skillName,
    String resourcePath,
  ) {
    if (logger.isEnabled(LogLevel.warning)) {
      logger.logWarning(
        'Skipped unsafe resource for $skillName: $resourcePath.',
      );
    }
  }

  static void logResourceSkippedExtension(
    Logger logger,
    String skillName,
    String filePath,
    String extensionValue,
  ) {
    if (logger.isEnabled(LogLevel.debug)) {
      logger.logDebug(
        'Skipped resource for $skillName due to extension $extensionValue: $filePath.',
      );
    }
  }

  static void logScriptPathTraversal(
    Logger logger,
    String skillName,
    String scriptPath,
  ) {
    if (logger.isEnabled(LogLevel.warning)) {
      logger.logWarning('Skipped unsafe script for $skillName: $scriptPath.');
    }
  }

  static void logDirectoryNameSkippedInvalid(
    Logger logger,
    String directoryName,
  ) {
    if (logger.isEnabled(LogLevel.debug)) {
      logger.logDebug('Skipped invalid directory name: $directoryName.');
    }
  }
}

import 'dart:convert';

import 'web_content_block.dart';

/// The parsed result of one extraction-script run: page metadata, typed
/// content blocks with heading paths, the heading outline, and any
/// machine-readable structured data.
///
/// The WebView script stays a thin DOM walker; everything here — kind
/// mapping, boilerplate flags, heading-path assignment, outline ranges,
/// JSON-LD parsing — happens in Dart so it is testable without a WebView.
class WebPageExtraction {
  WebPageExtraction._({
    required this.title,
    required this.canonicalUrl,
    required this.description,
    required this.siteName,
    required this.published,
    required this.modified,
    required this.author,
    required this.blocks,
    required this.outline,
    required this.structuredData,
    required this.challenge,
    required this.omittedBlocks,
    required this._fallbackText,
  });

  /// The document title, when present.
  final String? title;

  /// The page-declared canonical URL, when present.
  final String? canonicalUrl;

  /// The page metadata description, when present.
  final String? description;

  /// The publishing site's name, from Open Graph metadata or JSON-LD.
  final String? siteName;

  /// The declared publication time, verbatim as found.
  final String? published;

  /// The declared modification time, verbatim as found.
  final String? modified;

  /// The declared author, when present.
  final String? author;

  /// The extracted blocks, in source order with heading paths assigned.
  final List<WebContentBlock> blocks;

  /// The heading outline over the non-boilerplate blocks.
  final List<WebPageOutlineSection> outline;

  /// Machine-readable data found on the page.
  final List<WebStructuredData> structuredData;

  /// Whether the page looks like a login, consent, CAPTCHA, or
  /// verification challenge (DOM selectors in the script plus text
  /// phrases checked here).
  final bool challenge;

  /// Blocks the script saw but could not emit under its in-script cap.
  final int omittedBlocks;

  final String _fallbackText;

  /// Links inside one block are capped at this many entries.
  static const int maxLinksPerBlock = 8;

  /// Structured-data entries retained per page.
  static const int maxStructuredEntries = 5;

  /// A structured-data payload longer than this (serialized) keeps only
  /// its schema type, flagged truncated.
  static const int maxStructuredCharacters = 2000;

  /// Blocks shorter than this are never marked as duplicates.
  static const int minDuplicateCharacters = 40;

  static const List<String> _challengePhrases = <String>[
    'verify you are human',
    'checking your browser',
    'unusual traffic',
    'access denied',
    'consent required',
  ];

  /// The readable page text: non-boilerplate, non-duplicate block texts in
  /// order, or the script's raw fallback when no blocks were extracted.
  String get plainText {
    final joined = [
      for (final block in blocks)
        if (!block.isBoilerplate &&
            block.duplicateOfIndex == null &&
            block.text.isNotEmpty)
          block.text,
    ].join('\n\n');
    return joined.isNotEmpty ? joined : _fallbackText;
  }

  /// Parses the raw extraction-script result.
  ///
  /// Lenient by design: malformed entries are skipped, missing fields
  /// default to empty, and an unrecognized shape yields an extraction
  /// with no blocks rather than an error.
  static WebPageExtraction parse(Map<String, Object?> raw) {
    final meta = raw['meta'] is Map
        ? (raw['meta'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final blocks = _parseBlocks(raw['blocks']);
    final structured = _parseStructured(raw['structured']);
    final emitted = (raw['totalBlocks'] as num?)?.toInt() ?? blocks.length;
    final fallbackText = _clean(raw['fallbackText']) ?? '';

    final title = _clean(meta['title']);
    final plainProbe = [
      for (final block in blocks.take(40)) block.text,
    ].join('\n');
    final challengeText = '${title ?? ''}\n$plainProbe\n$fallbackText'
        .toLowerCase();
    final challenge =
        raw['challenge'] == true ||
        _challengePhrases.any(challengeText.contains);

    return WebPageExtraction._(
      title: title,
      canonicalUrl: _clean(meta['canonicalUrl']),
      description: _clean(meta['description']),
      siteName:
          _clean(meta['siteName']) ?? _fromStructured(structured, _ldSiteName),
      published:
          _clean(meta['published']) ??
          _fromStructured(
            structured,
            (data) => _ldString(data, 'datePublished'),
          ),
      modified:
          _clean(meta['modified']) ??
          _fromStructured(
            structured,
            (data) => _ldString(data, 'dateModified'),
          ),
      author: _clean(meta['author']) ?? _fromStructured(structured, _ldAuthor),
      blocks: blocks,
      outline: _buildOutline(blocks),
      structuredData: structured,
      challenge: challenge,
      omittedBlocks: emitted > blocks.length ? emitted - blocks.length : 0,
      fallbackText: fallbackText,
    );
  }

  static List<WebContentBlock> _parseBlocks(Object? rawBlocks) {
    if (rawBlocks is! List) return const <WebContentBlock>[];
    final blocks = <WebContentBlock>[];
    final headingStack = <({int level, String text})>[];
    final seenText = <String, int>{};
    for (final entry in rawBlocks) {
      if (entry is! Map) continue;
      final map = entry.cast<String, Object?>();
      final type = _kindOf((map['kind'] ?? '').toString());
      final text = _clean(map['text']) ?? '';
      final items = _stringList(map['items']);
      final table = type == WebContentBlockType.table
          ? _parseTable(map['table'])
          : null;
      if (text.isEmpty && items.isEmpty && table == null) continue;

      final container = (map['container'] ?? '').toString();
      final boilerplate = const <String>{
        'nav',
        'header',
        'footer',
        'aside',
      }.contains(container);
      final level = type == WebContentBlockType.heading
          ? ((map['level'] as num?)?.toInt() ?? 1).clamp(1, 6)
          : null;

      // Boilerplate headings (a footer's "Company" column) must not
      // reshape the content hierarchy.
      if (type == WebContentBlockType.heading && !boilerplate) {
        while (headingStack.isNotEmpty && headingStack.last.level >= level!) {
          headingStack.removeLast();
        }
      }

      // Repeated text — print footers, mobile and desktop copies of one
      // element — is marked, not dropped, so it stays expandable but is
      // never mistaken for independent confirmation. Short strings repeat
      // legitimately (labels, prices), so only substantial text counts.
      final normalized = <String>[
        text,
        ...items,
      ].join('\n').toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      int? duplicateOf;
      if (normalized.length >= minDuplicateCharacters) {
        duplicateOf = seenText[normalized];
        seenText[normalized] ??= blocks.length;
      }

      blocks.add(
        WebContentBlock(
          index: blocks.length,
          type: type,
          text: text,
          level: level,
          headingPath: [for (final entry in headingStack) entry.text],
          isBoilerplate: boilerplate,
          domPath: _clean(map['path']),
          links: _parseLinks(map['links']),
          listItems: items,
          ordered: map['ordered'] == true,
          table: table,
          duplicateOfIndex: duplicateOf,
        ),
      );

      if (type == WebContentBlockType.heading && !boilerplate) {
        headingStack.add((level: level!, text: text));
      }
    }
    return blocks;
  }

  static WebContentBlockType _kindOf(String kind) => switch (kind) {
    'heading' => WebContentBlockType.heading,
    'paragraph' => WebContentBlockType.paragraph,
    'list' => WebContentBlockType.list,
    'table' => WebContentBlockType.table,
    'code' => WebContentBlockType.code,
    'quote' => WebContentBlockType.quote,
    'definition' => WebContentBlockType.definition,
    'media' => WebContentBlockType.media,
    'form' => WebContentBlockType.form,
    _ => WebContentBlockType.other,
  };

  static List<WebContentLink> _parseLinks(Object? rawLinks) {
    if (rawLinks is! List) return const <WebContentLink>[];
    final seen = <String>{};
    final links = <WebContentLink>[];
    for (final entry in rawLinks) {
      if (links.length >= maxLinksPerBlock) break;
      if (entry is! Map) continue;
      final url = Uri.tryParse((entry['h'] ?? '').toString());
      if (url == null ||
          !url.hasAuthority ||
          (url.scheme != 'http' && url.scheme != 'https') ||
          !seen.add(url.toString())) {
        continue;
      }
      final text = _clean(entry['t']) ?? '';
      links.add(
        WebContentLink(
          text: text.isEmpty ? url.host : text,
          url: url.toString(),
        ),
      );
    }
    return links;
  }

  static WebContentTable? _parseTable(Object? rawTable) {
    if (rawTable is! Map) return null;
    final rows = <List<String>>[
      if (rawTable['rows'] case final List rawRows)
        for (final row in rawRows)
          if (row is List) [for (final cell in row) _clean(cell) ?? ''],
    ];
    final columns = _stringList(rawTable['columns']);
    if (rows.isEmpty && columns.isEmpty) return null;
    return WebContentTable(
      caption: _clean(rawTable['caption']),
      columns: columns,
      rows: rows,
    );
  }

  static List<WebStructuredData> _parseStructured(Object? rawStructured) {
    if (rawStructured is! List) return const <WebStructuredData>[];
    final entries = <WebStructuredData>[];
    for (final rawEntry in rawStructured) {
      if (entries.length >= maxStructuredEntries) break;
      if (rawEntry is! String || rawEntry.trim().isEmpty) continue;
      Object? decoded;
      try {
        decoded = jsonDecode(rawEntry);
      } on FormatException {
        continue;
      }
      // A top-level @graph list carries the entries; a plain list is used
      // directly. Each element becomes its own labeled entry.
      final nodes = switch (decoded) {
        final Map map when map['@graph'] is List => map['@graph'] as List,
        final List list => list,
        _ => <Object?>[decoded],
      };
      for (final node in nodes) {
        if (entries.length >= maxStructuredEntries) break;
        if (node is! Map) continue;
        final schemaType = _ldType(node);
        final oversize = rawEntry.length > maxStructuredCharacters;
        entries.add(
          WebStructuredData(
            format: 'json-ld',
            schemaType: schemaType,
            data: oversize ? null : node,
            truncated: oversize,
          ),
        );
      }
    }
    return entries;
  }

  static List<WebPageOutlineSection> _buildOutline(
    List<WebContentBlock> blocks,
  ) {
    final sections = <WebPageOutlineSection>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (block.type != WebContentBlockType.heading || block.isBoilerplate) {
        continue;
      }
      var last = i;
      for (var j = i + 1; j < blocks.length; j++) {
        final next = blocks[j];
        if (next.type == WebContentBlockType.heading &&
            !next.isBoilerplate &&
            next.level! <= block.level!) {
          break;
        }
        // Interleaved chrome (a mid-page ad rail, the footer) is not part
        // of any content section.
        if (!next.isBoilerplate) last = j;
      }
      sections.add(
        WebPageOutlineSection(
          heading: block.text,
          level: block.level!,
          firstBlockIndex: i,
          lastBlockIndex: last,
        ),
      );
    }
    return sections;
  }

  static String? _fromStructured(
    List<WebStructuredData> entries,
    String? Function(Map<String, Object?> data) pick,
  ) {
    for (final entry in entries) {
      if (entry.data case final Map data) {
        final value = pick(data.cast<String, Object?>());
        if (value != null) return value;
      }
    }
    return null;
  }

  static String? _ldType(Map<dynamic, dynamic> node) {
    final type = node['@type'];
    if (type is String && type.isNotEmpty) return type;
    if (type is List && type.isNotEmpty) return type.first.toString();
    return null;
  }

  static String? _ldString(Map<String, Object?> data, String key) =>
      _clean(data[key] is String ? data[key] : null);

  static String? _ldAuthor(Map<String, Object?> data) {
    final author = data['author'];
    return switch (author) {
      final String name => _clean(name),
      final Map map => _clean(map['name']),
      final List list when list.isNotEmpty && list.first is Map => _clean(
        (list.first as Map)['name'],
      ),
      _ => null,
    };
  }

  static String? _ldSiteName(Map<String, Object?> data) {
    final publisher = data['publisher'];
    return publisher is Map ? _clean(publisher['name']) : null;
  }

  static String? _clean(Object? value) {
    final text = value?.toString().replaceAll('\r', '').trim();
    return text == null || text.isEmpty ? null : text;
  }

  static List<String> _stringList(Object? value) => value is! List
      ? const <String>[]
      : [for (final entry in value) ?_clean(entry)];
}

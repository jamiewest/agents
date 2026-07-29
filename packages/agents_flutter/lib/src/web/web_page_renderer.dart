import 'web_content_block.dart';
import 'web_page_extraction.dart';

/// The rendered evidence markdown for one page, plus what was left out.
typedef RenderedWebPageMarkdown = ({
  /// The markdown handed to the model.
  String markdown,

  /// Content blocks dropped because [maxCharacters] ran out.
  int omittedForBudget,

  /// Blocks suppressed as navigation/footer/aside chrome.
  int boilerplateBlocks,
});

/// Renders extracted page blocks as compact markdown under a character
/// budget.
///
/// The header states the facts — source host, site name, published and
/// modified times, author — and the body renders blocks in source order,
/// skipping boilerplate. Rendering stops when [maxCharacters] runs out;
/// the count of dropped blocks is reported, never silent. (Query-aware
/// selection replaces the in-order cutoff in Phase 3.)
RenderedWebPageMarkdown renderWebPageMarkdown({
  required WebPageExtraction extraction,
  required Uri sourceUrl,
  required int maxCharacters,
}) {
  final buffer = StringBuffer();
  buffer.writeln('# ${extraction.title ?? sourceUrl.host}');
  final facts = <String>[
    'Source: ${sourceUrl.host}',
    if (extraction.siteName case final siteName?
        when siteName != sourceUrl.host)
      'Site: $siteName',
    if (extraction.published case final published?) 'Published: $published',
    if (extraction.modified case final modified?) 'Modified: $modified',
    if (extraction.author case final author?) 'Author: $author',
  ];
  buffer.writeln(facts.join(' · '));
  if (extraction.canonicalUrl case final canonical?
      when canonical != sourceUrl.toString()) {
    buffer.writeln('Canonical: $canonical');
  }

  var omitted = 0;
  var boilerplate = 0;
  var stopped = false;
  for (final block in extraction.blocks) {
    if (block.isBoilerplate) {
      boilerplate++;
      continue;
    }
    // Duplicates are marked in the block data and counted on the page
    // result; repeating them in the markdown would only spend tokens.
    if (block.duplicateOfIndex != null) continue;
    if (stopped) {
      omitted++;
      continue;
    }
    var rendered = _renderBlock(block);
    if (rendered.isEmpty) continue;
    final remaining = maxCharacters - buffer.length;
    if (rendered.length + 1 > remaining) {
      // A lone oversized block (a huge code listing) is clipped rather
      // than dropped, so the budget always yields some content.
      if (buffer.length < maxCharacters ~/ 2 && remaining > 200) {
        buffer
          ..writeln()
          ..writeln(rendered.substring(0, remaining));
      } else {
        omitted++;
      }
      stopped = true;
      continue;
    }
    buffer
      ..writeln()
      ..writeln(rendered);
  }

  return (
    markdown: buffer.toString().trimRight(),
    omittedForBudget: omitted,
    boilerplateBlocks: boilerplate,
  );
}

/// Renders [blocks] as markdown under [maxCharacters], for `expand_page`
/// and query-focused selections.
///
/// With [includeHeadingContext], each run of blocks under a new heading
/// path is prefixed with an `Under: A > B` line so expanded fragments keep
/// their place in the page. With [markGaps], a `[…]` line marks every jump
/// over unselected source blocks, so a focused selection never reads as
/// the whole page. Rendering stops when the budget runs out; the
/// dropped-block count is reported, never silent.
({String markdown, int omittedForBudget}) renderWebContentBlocks(
  List<WebContentBlock> blocks, {
  required int maxCharacters,
  bool includeHeadingContext = false,
  bool markGaps = false,
}) {
  final buffer = StringBuffer();
  List<String>? lastPath;
  int? lastIndex;
  var omitted = 0;
  var stopped = false;
  for (final block in blocks) {
    if (stopped) {
      omitted++;
      continue;
    }
    var rendered = _renderBlock(block);
    if (rendered.isEmpty) continue;
    if (includeHeadingContext &&
        block.headingPath.isNotEmpty &&
        block.type != WebContentBlockType.heading &&
        !_listEquals(block.headingPath, lastPath)) {
      rendered = 'Under: ${block.headingPath.join(' > ')}\n$rendered';
    }
    if (markGaps && lastIndex != null && block.index > lastIndex + 1) {
      rendered = '[…]\n$rendered';
    }
    final remaining = maxCharacters - buffer.length;
    if (rendered.length + 1 > remaining) {
      if (buffer.length < maxCharacters ~/ 2 && remaining > 200) {
        buffer
          ..writeln()
          ..writeln(rendered.substring(0, remaining));
      } else {
        omitted++;
      }
      stopped = true;
      continue;
    }
    buffer
      ..writeln()
      ..writeln(rendered);
    lastPath = block.headingPath;
    lastIndex = block.index;
  }
  return (markdown: buffer.toString().trim(), omittedForBudget: omitted);
}

bool _listEquals(List<String> a, List<String>? b) =>
    b != null &&
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

String _renderBlock(WebContentBlock block) {
  final body = switch (block.type) {
    WebContentBlockType.heading =>
      '${'#' * ((block.level ?? 1) + 1).clamp(2, 6)} ${block.text}',
    WebContentBlockType.list => _renderList(block),
    WebContentBlockType.definition => [
      for (final item in block.listItems) '- $item',
    ].join('\n'),
    WebContentBlockType.table => _renderTable(block),
    WebContentBlockType.code => '```\n${block.text}\n```',
    WebContentBlockType.quote => [
      for (final line in block.text.split('\n')) '> $line',
    ].join('\n'),
    WebContentBlockType.media => '(image: ${block.text})',
    WebContentBlockType.form => 'Form: ${block.text}',
    WebContentBlockType.paragraph || WebContentBlockType.other => block.text,
  };
  if (body.isEmpty) return '';
  // Headings and lists carry their own links as items; paragraphs and
  // tables surface theirs so download or detail links stay reachable.
  final links = switch (block.type) {
    WebContentBlockType.paragraph ||
    WebContentBlockType.table ||
    WebContentBlockType.other => block.links,
    _ => const <WebContentLink>[],
  };
  if (links.isEmpty) return body;
  final linkLine = [
    for (final link in links) '[${link.text}](${link.url})',
  ].join(' · ');
  return '$body\nLinks: $linkLine';
}

String _renderList(WebContentBlock block) {
  if (block.listItems.isEmpty) return block.text;
  return [
    for (final (i, item) in block.listItems.indexed)
      block.ordered ? '${i + 1}. $item' : '- $item',
  ].join('\n');
}

String _renderTable(WebContentBlock block) {
  final table = block.table;
  if (table == null || table.rows.isEmpty && table.columns.isEmpty) {
    return block.text;
  }
  final width = table.columns.isNotEmpty
      ? table.columns.length
      : table.rows.map((row) => row.length).reduce((a, b) => a > b ? a : b);
  String row(List<String> cells) =>
      '| ${[for (var i = 0; i < width; i++) _cell(cells, i)].join(' | ')} |';
  final lines = <String>[
    if (table.caption case final caption?) '**$caption**',
    row(table.columns.isNotEmpty ? table.columns : table.rows.first),
    '|${' --- |' * width}',
    for (final cells
        in table.columns.isNotEmpty ? table.rows : table.rows.skip(1))
      row(cells),
  ];
  return lines.join('\n');
}

String _cell(List<String> cells, int index) =>
    (index < cells.length ? cells[index] : '').replaceAll('|', r'\|');

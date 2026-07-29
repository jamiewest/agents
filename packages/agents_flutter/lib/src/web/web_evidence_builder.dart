import 'dart:collection';
import 'dart:math';

import 'web_block_scorer.dart';
import 'web_content_block.dart';
import 'web_page_loader.dart';
import 'web_page_renderer.dart';

/// The blocks chosen to serve one query, in source order, plus what was
/// left out.
typedef WebEvidenceSelection = ({
  /// The selected blocks — matches with their heading and short-intro
  /// companions — ordered as they appear on the page.
  List<WebContentBlock> blocks,

  /// Content blocks (headings excluded) that matched nothing or did not
  /// fit the budget.
  int omittedContentBlocks,

  /// Whether anything matched at all; `false` means the caller should
  /// keep the page's lead content instead.
  bool anyMatch,
});

/// Chooses the blocks that best serve [query] under [maxCharacters].
///
/// Ranking comes from [scorer]; selection then applies adjacency
/// grouping: a chosen block always brings the heading blocks above it and
/// a short intro paragraph directly before it, so a bare `$25` table row
/// can never travel without its "Fees" heading. Only matching blocks are
/// selected — a focused package stays focused, and the page outline
/// covers everything else. Boilerplate and duplicate blocks are never
/// selected.
Future<WebEvidenceSelection> selectQueryEvidence({
  required List<WebContentBlock> blocks,
  required String query,
  required int maxCharacters,
  BlockScorer scorer = const LexicalBlockScorer(),
}) async {
  final scores = await scorer.score(query, blocks);
  final headingIndexes = _governingHeadings(blocks);

  final candidates =
      <int>[
        for (var i = 0; i < blocks.length; i++)
          if (_isContent(blocks[i]) && scores[i] > 0) i,
      ]..sort((a, b) {
        final byScore = scores[b].compareTo(scores[a]);
        return byScore != 0 ? byScore : a.compareTo(b);
      });
  final contentBlockCount = blocks.where(_isContent).length;
  if (candidates.isEmpty) {
    return (
      blocks: const <WebContentBlock>[],
      omittedContentBlocks: contentBlockCount,
      anyMatch: false,
    );
  }

  final selected = SplayTreeSet<int>();
  var budget = maxCharacters;
  for (final index in candidates) {
    if (selected.contains(index)) continue;
    final addition = <int>{
      index,
      ...headingIndexes[index] ?? const <int>[],
      ..._shortIntroBefore(blocks, index),
    }..removeAll(selected);
    final cost = addition.fold(0, (sum, i) => sum + _costOf(blocks[i]));
    // The best match must always survive the budget — the renderer clips
    // it if it is oversized — otherwise skip what does not fit and keep
    // trying smaller candidates.
    if (cost > budget && selected.isNotEmpty) continue;
    budget = max(0, budget - cost);
    selected.addAll(addition);
  }

  final selectedContent = selected.where((i) => _isContent(blocks[i])).length;
  return (
    blocks: [for (final index in selected) blocks[index]],
    omittedContentBlocks: contentBlockCount - selectedContent,
    anyMatch: true,
  );
}

/// Builds the query-focused evidence markdown for an opened page:
/// the facts header, a `Focused on:` marker, and the selected blocks with
/// gap markers.
///
/// Returns `anyMatch: false` — with empty markdown — when nothing in the
/// page matched, so the caller can keep the lead-content rendering
/// instead of returning an empty package.
Future<({String markdown, int omittedContentBlocks, bool anyMatch})>
buildQueryAwareEvidence({
  required WebPageContent content,
  required String objective,
  required int maxCharacters,
  BlockScorer scorer = const LexicalBlockScorer(),
}) async {
  final source = content.finalUrl ?? content.requestedUrl;
  final header = StringBuffer()
    ..writeln('# ${content.title ?? source.host}')
    ..writeln(
      <String>[
        'Source: ${source.host}',
        if (content.siteName case final siteName? when siteName != source.host)
          'Site: $siteName',
        if (content.publishedTime case final published?)
          'Published: $published',
        if (content.modifiedTime case final modified?) 'Modified: $modified',
        if (content.author case final author?) 'Author: $author',
      ].join(' · '),
    )
    ..writeln('Focused on: $objective');

  final bodyBudget = maxCharacters - header.length;
  final selection = await selectQueryEvidence(
    blocks: content.blocks,
    query: objective,
    maxCharacters: bodyBudget,
    scorer: scorer,
  );
  if (!selection.anyMatch) {
    return (markdown: '', omittedContentBlocks: 0, anyMatch: false);
  }
  final rendered = renderWebContentBlocks(
    selection.blocks,
    maxCharacters: bodyBudget,
    markGaps: true,
  );
  return (
    markdown: '$header\n${rendered.markdown}',
    omittedContentBlocks:
        selection.omittedContentBlocks + rendered.omittedForBudget,
    anyMatch: true,
  );
}

/// Maps each block index to the indices of the heading blocks above it.
Map<int, List<int>> _governingHeadings(List<WebContentBlock> blocks) {
  final result = <int, List<int>>{};
  final stack = <({int level, int index})>[];
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    if (block.type == WebContentBlockType.heading && !block.isBoilerplate) {
      while (stack.isNotEmpty && stack.last.level >= block.level!) {
        stack.removeLast();
      }
      result[i] = [for (final entry in stack) entry.index];
      stack.add((level: block.level!, index: i));
    } else {
      result[i] = [for (final entry in stack) entry.index];
    }
  }
  return result;
}

/// The index of a short intro paragraph directly before [index] in the
/// same section — "The following charges apply." before a fee table —
/// or none.
Iterable<int> _shortIntroBefore(List<WebContentBlock> blocks, int index) {
  if (index == 0) return const <int>[];
  final previous = blocks[index - 1];
  final block = blocks[index];
  final sameSection =
      previous.headingPath.length == block.headingPath.length &&
      [
        for (var i = 0; i < previous.headingPath.length; i++)
          previous.headingPath[i] == block.headingPath[i],
      ].every((same) => same);
  return previous.type == WebContentBlockType.paragraph &&
          _isContent(previous) &&
          sameSection &&
          previous.text.length <= 240
      ? [index - 1]
      : const <int>[];
}

bool _isContent(WebContentBlock block) =>
    !block.isBoilerplate &&
    block.duplicateOfIndex == null &&
    block.type != WebContentBlockType.heading;

/// Approximate rendered size; the renderer enforces the hard budget.
int _costOf(WebContentBlock block) {
  var cost = block.text.length + 24;
  for (final item in block.listItems) {
    cost += item.length + 3;
  }
  if (block.table case final table?) {
    for (final column in table.columns) {
      cost += column.length + 3;
    }
    for (final row in table.rows) {
      for (final cell in row) {
        cost += cell.length + 3;
      }
    }
  }
  for (final link in block.links) {
    cost += link.text.length + link.url.length + 6;
  }
  return cost;
}

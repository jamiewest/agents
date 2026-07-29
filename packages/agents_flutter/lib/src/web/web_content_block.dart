/// The structural kind of one extracted content block.
///
/// Boilerplate is a flag on [WebContentBlock], not a kind: a link list
/// inside a `<nav>` is still a [list], just one flagged as boilerplate.
enum WebContentBlockType {
  /// A section heading (h1–h6); [WebContentBlock.level] carries its depth.
  heading,

  /// Running text.
  paragraph,

  /// A bulleted or numbered list; items are in [WebContentBlock.listItems].
  list,

  /// A data table; cells are in [WebContentBlock.table].
  table,

  /// Preformatted code or terminal output.
  code,

  /// A block quotation.
  quote,

  /// A definition list of term–description pairs.
  definition,

  /// An image or figure, represented by its alternative text.
  media,

  /// A form summarized by its labels and controls.
  form,

  /// Anything the extractor could not classify further.
  other,
}

/// One hyperlink found inside a content block.
class WebContentLink {
  /// Creates a link.
  const WebContentLink({required this.text, required this.url});

  /// The link's visible text.
  final String text;

  /// The absolute HTTP or HTTPS destination.
  final String url;

  /// Converts this link to JSON.
  Map<String, Object?> toJson() => <String, Object?>{'text': text, 'url': url};
}

/// Tabular cells extracted from a table block.
class WebContentTable {
  /// Creates a table.
  const WebContentTable({
    this.caption,
    this.columns = const <String>[],
    this.rows = const <List<String>>[],
  });

  /// The table caption, when present.
  final String? caption;

  /// Header cell texts, empty when the table declares no header.
  final List<String> columns;

  /// Body rows of cell texts.
  final List<List<String>> rows;

  /// Converts this table to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    if (caption != null) 'caption': caption,
    if (columns.isNotEmpty) 'columns': columns,
    'rows': rows,
  };
}

/// One semantic block extracted from a web page, in source order.
///
/// Blocks are the unit the evidence pipeline ranks, renders, and — from
/// Phase 2 — lets the model expand by identifier. [headingPath] carries the
/// page's heading hierarchy above the block, so "Electronic copies are $25"
/// stays attached to its "Fees" section.
class WebContentBlock {
  /// Creates a content block.
  const WebContentBlock({
    required this.index,
    required this.type,
    required this.text,
    this.level,
    this.headingPath = const <String>[],
    this.isBoilerplate = false,
    this.domPath,
    this.links = const <WebContentLink>[],
    this.listItems = const <String>[],
    this.ordered = false,
    this.table,
    this.duplicateOfIndex,
  });

  /// Source-order position; also the basis of the block's `b<index>` id.
  final int index;

  /// The block's structural kind.
  final WebContentBlockType type;

  /// The block's visible text. For lists and tables this is a compact
  /// rendition; the structured cells live in [listItems] and [table].
  final String text;

  /// Heading depth 1–6, for [WebContentBlockType.heading] blocks.
  final int? level;

  /// Texts of the headings above this block, outermost first.
  final List<String> headingPath;

  /// Whether the block sits in navigation, header, footer, or aside
  /// chrome rather than page content.
  final bool isBoilerplate;

  /// A short element path such as `main>section:2>p:1`, when known.
  final String? domPath;

  /// HTTP(S) links found inside the block.
  final List<WebContentLink> links;

  /// Item texts, for [WebContentBlockType.list] blocks.
  final List<String> listItems;

  /// Whether a list block was numbered rather than bulleted.
  final bool ordered;

  /// Extracted cells, for [WebContentBlockType.table] blocks.
  final WebContentTable? table;

  /// Index of the earlier block this one repeats verbatim, or `null` for
  /// original content.
  ///
  /// Marked so repeated text — print footers, syndication banners, mobile
  /// and desktop copies of one element — is never mistaken for
  /// independent confirmation. Duplicates are skipped by ranking and
  /// rendering but remain expandable by id.
  final int? duplicateOfIndex;

  /// The identifier the model uses to reference this block.
  String get id => 'b$index';

  /// Converts this block to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type.name,
    if (level != null) 'level': level,
    if (headingPath.isNotEmpty) 'headingPath': headingPath,
    if (isBoilerplate) 'boilerplate': true,
    if (duplicateOfIndex != null) 'duplicateOf': 'b$duplicateOfIndex',
    if (domPath != null) 'domPath': domPath,
    'text': text,
    if (listItems.isNotEmpty) 'items': listItems,
    if (ordered) 'ordered': true,
    if (table != null) 'table': table!.toJson(),
    if (links.isNotEmpty)
      'links': <Object?>[for (final link in links) link.toJson()],
  };
}

/// One entry of a page's heading outline: a heading and the block range
/// it governs, up to the next heading of the same or higher level.
class WebPageOutlineSection {
  /// Creates an outline section.
  const WebPageOutlineSection({
    required this.heading,
    required this.level,
    required this.firstBlockIndex,
    required this.lastBlockIndex,
  });

  /// The heading text.
  final String heading;

  /// The heading depth 1–6.
  final int level;

  /// Index of the heading block itself.
  final int firstBlockIndex;

  /// Index of the last block governed by this heading.
  final int lastBlockIndex;

  /// A compact one-line rendition, e.g. `## Fees [b12-b18]`.
  String describe() =>
      '${'#' * level} $heading '
      '[b$firstBlockIndex${lastBlockIndex == firstBlockIndex ? '' : '-b$lastBlockIndex'}]';
}

/// Machine-readable data found on a page, labeled by origin.
class WebStructuredData {
  /// Creates a structured-data entry.
  const WebStructuredData({
    required this.format,
    this.schemaType,
    this.data,
    this.truncated = false,
  });

  /// Where the data came from: `json-ld` today.
  final String format;

  /// The declared schema.org type, when present.
  final String? schemaType;

  /// The parsed payload, or `null` when only [schemaType] is retained.
  final Object? data;

  /// Whether [data] was dropped or clipped for size.
  final bool truncated;

  /// Converts this entry to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'format': format,
    if (schemaType != null) 'schemaType': schemaType,
    if (data != null) 'data': data,
    if (truncated) 'truncated': true,
  };
}

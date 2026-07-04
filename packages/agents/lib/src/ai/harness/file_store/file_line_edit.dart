/// Represents a single whole-line replacement used by the file access and
/// file memory `replace_lines` tools.
class FileLineEdit {
  /// Creates a line edit replacing [lineNumber] with [newLine].
  FileLineEdit({required this.lineNumber, required this.newLine});

  /// Creates a [FileLineEdit] from a JSON-decoded map using the wire keys
  /// `line_number` and `new_line`.
  factory FileLineEdit.fromJson(Map<String, Object?> json) => FileLineEdit(
    lineNumber: (json['line_number'] as num).toInt(),
    newLine: json['new_line'] as String? ?? '',
  );

  /// The 1-based line number to replace.
  final int lineNumber;

  /// The literal replacement text for the line, including any trailing
  /// newline to keep — the editor does not add one. An empty string deletes
  /// the line entirely (its content and its line break).
  final String newLine;

  /// Encodes this edit using the wire keys `line_number` and `new_line`.
  Map<String, Object?> toJson() => {
    'line_number': lineNumber,
    'new_line': newLine,
  };
}

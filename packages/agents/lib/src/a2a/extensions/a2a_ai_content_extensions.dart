import 'dart:convert';
import 'dart:typed_data';

import 'package:a2a/a2a.dart';
import 'package:extensions/ai.dart';

/// Converts an [AIContent] item to an [A2APart], or `null` if the content
/// type has no A2A representation.
A2APart? _toPart(AIContent content) {
  if (content is TextContent) {
    return A2ATextPart()..text = content.text;
  }
  if (content is DataContent) {
    final bytes = content.data;
    if (bytes != null) {
      return A2AFilePart()
        ..file = (A2AFileWithBytes()
          ..bytes = base64.encode(bytes)
          ..mimeType = content.mediaType ?? ''
          ..name = content.name ?? '');
    }
    final uri = content.uri;
    if (uri != null) {
      return A2AFilePart()
        ..file = (A2AFileWithUri()
          ..uri = uri
          ..mimeType = content.mediaType ?? '');
    }
    return null;
  }
  if (content is UriContent) {
    return A2AFilePart()
      ..file = (A2AFileWithUri()
        ..uri = content.uri.toString()
        ..mimeType = content.mediaType);
  }
  return null;
}

/// Converts an [A2APart] to an [AIContent].
AIContent _toAIContent(A2APart part) {
  if (part is A2ATextPart) {
    return TextContent(part.text);
  }
  if (part is A2AFilePart) {
    final file = part.file;
    if (file is A2AFileWithBytes) {
      final bytes = base64.decode(file.bytes);
      return DataContent(
        Uint8List.fromList(bytes),
        mediaType: file.mimeType.isEmpty ? 'application/octet-stream' : file.mimeType,
        name: file.name.isEmpty ? null : file.name,
      );
    }
    if (file is A2AFileWithUri) {
      return UriContent(
        Uri.parse(file.uri),
        mediaType: file.mimeType.isEmpty ? 'application/octet-stream' : file.mimeType,
      );
    }
  }
  if (part is A2ADataPart) {
    final json = jsonEncode(part.data);
    return DataContent(
      Uint8List.fromList(utf8.encode(json)),
      mediaType: 'application/json',
    );
  }
  return TextContent('');
}

/// Extension methods for converting [AIContent] collections to A2A [A2APart]
/// lists and back.
extension A2AAIContentExtensions on Iterable<AIContent> {
  /// Converts this collection to a list of [A2APart] objects, skipping any
  /// content that has no A2A representation.
  List<A2APart>? toParts() {
    List<A2APart>? parts;
    for (final content in this) {
      final part = _toPart(content);
      if (part != null) {
        (parts ??= []).add(part);
      }
    }
    return parts;
  }
}

/// Extension methods for converting an [A2APart] to an [AIContent].
extension A2APartExtensions on A2APart {
  /// Converts this [A2APart] to an [AIContent].
  AIContent toAIContent() => _toAIContent(this);
}

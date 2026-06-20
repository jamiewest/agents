// Copyright (c) Microsoft. All rights reserved.
//
// Ported from ChatCompletions/Converters/MessageContentPartConverter.cs.

import 'dart:convert';

import 'package:extensions/ai.dart';

import '../models/message_content.dart';

/// Converts request [MessageContentPart] items to `extensions/ai` [AIContent].
class MessageContentPartConverter {
  MessageContentPartConverter._();

  /// Converts a [MessageContentPart] to an [AIContent], or null when the part
  /// has no representation.
  static AIContent? toAIContent(MessageContentPart part) {
    if (part is TextContentPart) {
      return TextContent(part.text);
    }

    if (part is ImageContentPart && part.urlOrData.isNotEmpty) {
      final urlOrData = part.urlOrData;
      if (urlOrData.toLowerCase().startsWith('data:')) {
        return DataContent.fromUri(urlOrData);
      }
      final uri = Uri.parse(urlOrData);
      return UriContent(uri, mediaType: _imageUriToMediaType(uri));
    }

    if (part is AudioContentPart) {
      return DataContent(
        base64Decode(part.inputAudio.data),
        mediaType: _audioFormatToMediaType(part.inputAudio.format),
      );
    }

    if (part is FileContentPart) {
      final file = part.file;
      if (file.fileId != null && file.fileId!.isNotEmpty) {
        return HostedFileContent(fileId: file.fileId!);
      }
      if (file.fileData != null && file.fileData!.isNotEmpty) {
        return DataContent(
          base64Decode(file.fileData!),
          mediaType: 'application/octet-stream',
          name: file.filename,
        );
      }
    }

    return null;
  }

  static String _audioFormatToMediaType(String format) {
    switch (format.toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'opus':
        return 'audio/opus';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'pcm16':
        return 'audio/pcm';
      default:
        return 'audio/*';
    }
  }

  static String _imageUriToMediaType(Uri uri) {
    final absolute = uri.toString().toLowerCase();
    if (absolute.endsWith('.png')) return 'image/png';
    if (absolute.endsWith('.jpg') || absolute.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (absolute.endsWith('.gif')) return 'image/gif';
    if (absolute.endsWith('.bmp')) return 'image/bmp';
    if (absolute.endsWith('.webp')) return 'image/webp';
    return 'image/*';
  }
}

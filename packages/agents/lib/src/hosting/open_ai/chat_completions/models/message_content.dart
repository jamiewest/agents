// Copyright (c) Microsoft. All rights reserved.
//
// Ported from ChatCompletions/Models/MessageContent.cs and
// ChatCompletions/Models/MessageContentPart.cs.

/// Content which is part of a chat completion request message.
///
/// Can be either a plain string ([text]) or a list of typed [contents] parts.
class MessageContent {
  const MessageContent._(this.text, this.contents);

  /// Creates a [MessageContent] from a text string.
  factory MessageContent.fromText(String text) => MessageContent._(text, null);

  /// Creates a [MessageContent] from a list of [MessageContentPart] items.
  factory MessageContent.fromContents(List<MessageContentPart> contents) =>
      MessageContent._(null, contents);

  /// Parses a [MessageContent] from a decoded JSON value (string or list).
  factory MessageContent.fromJson(Object? json) {
    if (json is String) {
      return MessageContent.fromText(json);
    }
    if (json is List) {
      final parts = json
          .whereType<Map<String, dynamic>>()
          .map(MessageContentPart.fromJson)
          .toList();
      return parts.isNotEmpty
          ? MessageContent.fromContents(parts)
          : MessageContent.fromText('');
    }
    throw FormatException('Unexpected MessageContent JSON: $json');
  }

  /// The text value, or null when this is a content list.
  final String? text;

  /// The content-part items, or null when this is a text value.
  final List<MessageContentPart>? contents;

  /// Whether this content is a plain text value.
  bool get isText => text != null;

  /// Whether this content is a list of content parts.
  bool get isContents => contents != null;

  /// Serializes this content as a string or list of parts.
  Object toJson() {
    if (isText) {
      return text!;
    }
    if (isContents) {
      return contents!.map((p) => p.toJson()).toList();
    }
    throw StateError('MessageContent has no value');
  }
}

/// A part of message content (text, image, audio, or file).
abstract class MessageContentPart {
  const MessageContentPart();

  /// Parses a content part from its JSON `type` discriminator.
  factory MessageContentPart.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'text':
        return TextContentPart(text: json['text'] as String);
      case 'image_url':
        return ImageContentPart(
          imageUrl: ImageUrl.fromJson(
            json['image_url'] as Map<String, dynamic>,
          ),
        );
      case 'input_audio':
        return AudioContentPart(
          inputAudio: InputAudio.fromJson(
            json['input_audio'] as Map<String, dynamic>,
          ),
        );
      case 'file':
        return FileContentPart(
          file: InputFile.fromJson(json['file'] as Map<String, dynamic>),
        );
      default:
        throw FormatException('Unknown content part type: $type');
    }
  }

  /// The wire `type` discriminator.
  String get type;

  /// Serializes this part including its `type` discriminator.
  Map<String, dynamic> toJson();
}

/// A text content part.
class TextContentPart extends MessageContentPart {
  /// Creates a [TextContentPart].
  const TextContentPart({required this.text});

  /// The text content.
  final String text;

  @override
  String get type => 'text';

  @override
  Map<String, dynamic> toJson() => {'type': type, 'text': text};
}

/// An image content part.
class ImageContentPart extends MessageContentPart {
  /// Creates an [ImageContentPart].
  const ImageContentPart({required this.imageUrl});

  /// Details about the image URL or base64-encoded image data.
  final ImageUrl imageUrl;

  /// The URL or base64 data of the image.
  String get urlOrData => imageUrl.url;

  @override
  String get type => 'image_url';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'image_url': imageUrl.toJson(),
  };
}

/// Details about an image for vision-enabled models.
class ImageUrl {
  /// Creates an [ImageUrl].
  const ImageUrl({required this.url, this.detail});

  /// Parses an [ImageUrl] from JSON.
  factory ImageUrl.fromJson(Map<String, dynamic> json) =>
      ImageUrl(url: json['url'] as String, detail: json['detail'] as String?);

  /// A URL of the image or base64-encoded image data.
  final String url;

  /// The detail level of the image.
  final String? detail;

  /// Serializes this image URL.
  Map<String, dynamic> toJson() => {
    'url': url,
    if (detail != null) 'detail': detail,
  };
}

/// An audio content part.
class AudioContentPart extends MessageContentPart {
  /// Creates an [AudioContentPart].
  const AudioContentPart({required this.inputAudio});

  /// The input audio data.
  final InputAudio inputAudio;

  @override
  String get type => 'input_audio';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'input_audio': inputAudio.toJson(),
  };
}

/// Input audio data for audio-enabled models.
class InputAudio {
  /// Creates an [InputAudio].
  const InputAudio({required this.data, required this.format});

  /// Parses an [InputAudio] from JSON.
  factory InputAudio.fromJson(Map<String, dynamic> json) => InputAudio(
    data: json['data'] as String,
    format: json['format'] as String,
  );

  /// Base64-encoded audio data.
  final String data;

  /// The format of the encoded audio data (for example `wav` or `mp3`).
  final String format;

  /// Serializes this input audio.
  Map<String, dynamic> toJson() => {'data': data, 'format': format};
}

/// A file content part.
class FileContentPart extends MessageContentPart {
  /// Creates a [FileContentPart].
  const FileContentPart({required this.file});

  /// The input file data.
  final InputFile file;

  @override
  String get type => 'file';

  @override
  Map<String, dynamic> toJson() => {'type': type, 'file': file.toJson()};
}

/// Input file data for file-enabled models.
class InputFile {
  /// Creates an [InputFile].
  const InputFile({this.fileData, this.fileId, this.filename});

  /// Parses an [InputFile] from JSON.
  factory InputFile.fromJson(Map<String, dynamic> json) => InputFile(
    fileData: json['file_data'] as String?,
    fileId: json['file_id'] as String?,
    filename: json['filename'] as String?,
  );

  /// The base64-encoded file data.
  final String? fileData;

  /// The ID of an uploaded file to use as input.
  final String? fileId;

  /// The name of the file.
  final String? filename;

  /// Serializes this input file, omitting null fields.
  Map<String, dynamic> toJson() => {
    if (fileData != null) 'file_data': fileData,
    if (fileId != null) 'file_id': fileId,
    if (filename != null) 'filename': filename,
  };
}

// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Microsoft.Agents.AI.Hosting.OpenAI/IdGenerator.cs.

import 'dart:math';

/// Generates IDs with partition keys.
///
/// IDs have the structured format `{prefix}{delimiter}{infix}{entropy}{pKey}`,
/// where the trailing partition key allows related IDs (for example all IDs
/// belonging to a single conversation) to share a routable suffix.
class IdGenerator {
  /// Creates an [IdGenerator].
  ///
  /// When [randomSeed] is provided a deterministic [Random] is used (useful for
  /// tests); otherwise IDs use [Random.secure].
  factory IdGenerator({
    String? responseId,
    String? conversationId,
    int? randomSeed,
  }) {
    final random = randomSeed != null ? Random(randomSeed) : null;
    return IdGenerator._(
      random,
      responseId ?? newId('resp', random: random),
      conversationId ?? newId('conv', random: random),
    );
  }

  IdGenerator._(this._random, this.responseId, this.conversationId)
    : _partitionId = _getPartitionIdOrDefault(conversationId) ?? '';

  static final RegExp _watermarkRegex = RegExp(r'^[A-Za-z0-9]+$');

  static const String _chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  final Random? _random;
  final String _partitionId;

  /// The response ID.
  final String responseId;

  /// The conversation ID.
  final String conversationId;

  /// Generates a new ID with the configured partition key.
  String generate([String? category]) {
    final prefix = (category == null || category.isEmpty) ? 'id' : category;
    return newId(prefix, partitionKey: _partitionId, random: _random);
  }

  /// Generates a function call ID.
  String generateFunctionCallId() => generate('func');

  /// Generates a function output ID.
  String generateFunctionOutputId() => generate('funcout');

  /// Generates a message ID.
  String generateMessageId() => generate('msg');

  /// Generates a reasoning ID.
  String generateReasoningId() => generate('rs');

  /// Generates a new ID with a structured format that includes a partition key.
  ///
  /// Returns a string of the form `{prefix}{delimiter}{infix}{entropy}{pKey}`.
  static String newId(
    String prefix, {
    int stringLength = 32,
    int partitionKeyLength = 16,
    String infix = '',
    String watermark = '',
    String delimiter = '_',
    String? partitionKey,
    String partitionKeyHint = '',
    Random? random,
  }) {
    if (stringLength < 1) {
      throw RangeError.value(stringLength, 'stringLength');
    }

    var entropy = _getRandomString(stringLength, random);

    final pKey =
        partitionKey ??
        _getPartitionIdOrDefault(partitionKeyHint) ??
        _getRandomString(partitionKeyLength, random);

    if (watermark.isNotEmpty) {
      if (!_watermarkRegex.hasMatch(watermark)) {
        throw ArgumentError.value(
          watermark,
          'watermark',
          'Only alphanumeric characters may be in watermark',
        );
      }
      final half = stringLength ~/ 2;
      entropy =
          '${entropy.substring(0, half)}$watermark${entropy.substring(half)}';
    }

    final prefixPart = prefix.isNotEmpty ? '$prefix$delimiter' : '';
    return '$prefixPart$infix$entropy$pKey';
  }

  /// Generates a random alphanumeric string of [stringLength] characters.
  ///
  /// Uses [random] when supplied; otherwise [Random.secure].
  static String _getRandomString(int stringLength, Random? random) {
    final rng = random ?? Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < stringLength; i++) {
      buffer.write(_chars[rng.nextInt(_chars.length)]);
    }
    return buffer.toString();
  }

  /// Extracts the partition key from an existing ID, or returns null.
  static String? _getPartitionIdOrDefault(
    String? id, {
    int stringLength = 32,
    int partitionKeyLength = 16,
    String delimiter = '_',
  }) {
    if (id == null || id.isEmpty) {
      return null;
    }

    final parts = id
        .split(delimiter)
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 2) {
      return null;
    }
    if (parts[1].length < stringLength + partitionKeyLength) {
      return null;
    }
    return parts[1].substring(parts[1].length - partitionKeyLength);
  }
}

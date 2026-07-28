import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

import 'pushover_api.dart';

/// The length, in bytes, of a Pushover end-to-end encryption key.
const int pushoverEncryptionKeyLength = 32;

/// The length, in bytes, of the random initialization vector.
const int pushoverEncryptionIvLength = 16;

/// The length, in bytes, of the trailing HMAC-SHA256 tag.
const int pushoverEncryptionMacLength = 32;

/// Encrypts one message field for Pushover's end-to-end encryption.
///
/// Each of `message`, `title`, `url`, and `url_title` is encrypted
/// independently, so implementations receive one field at a time and must be
/// safe to call repeatedly.
typedef PushoverFieldEncryptor = String Function(String plaintext);

/// Implements Pushover's end-to-end encryption scheme.
///
/// The 256-bit key lives on the recipient's device and is never sent to
/// Pushover, so senders must hold a copy independently. Per the API docs, each
/// field is gzip compressed, encrypted with AES-256-CBC and PKCS7 padding
/// under a fresh random IV, authenticated with HMAC-SHA256 over IV and
/// ciphertext, and transmitted as `base64(iv + ciphertext + mac)`.
///
/// Only `message`, `title`, `url`, and `url_title` are encrypted. Routing
/// fields such as `sound`, `device`, and `priority` stay in the clear because
/// Pushover's servers act on them.
final class PushoverAesEncryptor {
  /// Creates an encryptor from a raw 32-byte [key].
  PushoverAesEncryptor(this.key, {Random? random})
    : _random = random ?? Random.secure() {
    if (key.length != pushoverEncryptionKeyLength) {
      throw ArgumentError.value(
        key.length,
        'key',
        'A Pushover encryption key must be exactly '
            '$pushoverEncryptionKeyLength bytes.',
      );
    }
  }

  /// Creates an encryptor from the 64-character hex key shown in the Pushover
  /// apps.
  factory PushoverAesEncryptor.fromHexKey(String hexKey, {Random? random}) {
    final normalized = hexKey.trim().toLowerCase();
    if (normalized.length != pushoverEncryptionKeyLength * 2 ||
        !RegExp(r'^[0-9a-f]+$').hasMatch(normalized)) {
      throw ArgumentError.value(
        hexKey,
        'hexKey',
        'A Pushover encryption key must be '
            '${pushoverEncryptionKeyLength * 2} hexadecimal characters.',
      );
    }
    return PushoverAesEncryptor(
      Uint8List.fromList([
        for (var i = 0; i < normalized.length; i += 2)
          int.parse(normalized.substring(i, i + 2), radix: 16),
      ]),
      random: random,
    );
  }

  /// The 256-bit shared key.
  final Uint8List key;

  final Random _random;

  /// Encrypts [plaintext] into Pushover's `base64(iv + ciphertext + mac)`
  /// envelope.
  ///
  /// Calling the instance directly lets it be passed wherever a
  /// [PushoverFieldEncryptor] is expected.
  String call(String plaintext) {
    final compressed = GZipEncoder().encodeBytes(utf8.encode(plaintext));
    final iv = Uint8List.fromList([
      for (var i = 0; i < pushoverEncryptionIvLength; i++) _random.nextInt(256),
    ]);
    final ciphertext = _cipher(forEncryption: true, iv: iv).process(compressed);
    final mac = _mac(iv, ciphertext);

    return base64.encode([...iv, ...ciphertext, ...mac]);
  }

  /// Reverses [call], recovering the plaintext from an envelope.
  ///
  /// Provided so senders can verify what they produced; the recipient's device
  /// is normally the only reader.
  String decrypt(String envelope) {
    final Uint8List bytes;
    try {
      bytes = base64.decode(envelope);
    } on FormatException catch (error) {
      throw PushoverApiException('Envelope is not valid base64. $error');
    }

    const overhead = pushoverEncryptionIvLength + pushoverEncryptionMacLength;
    if (bytes.length <= overhead) {
      throw const PushoverApiException(
        'Envelope is too short to contain an IV, ciphertext, and MAC.',
      );
    }

    final iv = Uint8List.sublistView(bytes, 0, pushoverEncryptionIvLength);
    final ciphertext = Uint8List.sublistView(
      bytes,
      pushoverEncryptionIvLength,
      bytes.length - pushoverEncryptionMacLength,
    );
    final mac = Uint8List.sublistView(
      bytes,
      bytes.length - pushoverEncryptionMacLength,
    );

    if (!_constantTimeEquals(mac, _mac(iv, ciphertext))) {
      throw const PushoverApiException(
        'Envelope failed authentication; the key or the data is wrong.',
      );
    }

    final compressed = _cipher(
      forEncryption: false,
      iv: iv,
    ).process(ciphertext);
    return utf8.decode(GZipDecoder().decodeBytes(compressed));
  }

  PaddedBlockCipherImpl _cipher({
    required bool forEncryption,
    required Uint8List iv,
  }) =>
      PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))..init(
        forEncryption,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV(KeyParameter(key), iv),
          null,
        ),
      );

  Uint8List _mac(Uint8List iv, Uint8List ciphertext) => Uint8List.fromList(
    crypto.Hmac(crypto.sha256, key).convert([...iv, ...ciphertext]).bytes,
  );

  /// Compares two tags without leaking where they first differ.
  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var mismatch = 0;
    for (var i = 0; i < a.length; i++) {
      mismatch |= a[i] ^ b[i];
    }
    return mismatch == 0;
  }
}

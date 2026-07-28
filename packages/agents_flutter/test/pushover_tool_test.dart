import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:agents_flutter/src/pushover/pushover_api.dart';
import 'package:agents_flutter/src/pushover/pushover_encryption.dart';
import 'package:agents_flutter/src/pushover/pushover_service_collection_extensions.dart';
import 'package:agents_flutter/src/pushover/pushover_tool.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the calls a client makes and replays canned responses.
class _FakeTransport {
  _FakeTransport({this.postResponses = const [], this.getResponses = const []});

  final List<PushoverHttpResponse> postResponses;
  final List<PushoverHttpResponse> getResponses;

  final List<Uri> postUrls = [];
  final List<Map<String, String>> postFields = [];
  final List<Uri> getUrls = [];
  final List<PushoverAttachment> attachments = [];

  Future<PushoverHttpResponse> post(Uri url, Map<String, String> fields) async {
    postUrls.add(url);
    postFields.add(fields);
    return postResponses.isEmpty
        ? _ok()
        : postResponses[postUrls.length - 1 < postResponses.length
              ? postUrls.length - 1
              : postResponses.length - 1];
  }

  Future<PushoverHttpResponse> postMultipart(
    Uri url,
    Map<String, String> fields,
    PushoverAttachment attachment,
  ) {
    attachments.add(attachment);
    return post(url, fields);
  }

  Future<PushoverHttpResponse> get(Uri url) async {
    getUrls.add(url);
    return getResponses.isEmpty
        ? _ok()
        : getResponses[getUrls.length - 1 < getResponses.length
              ? getUrls.length - 1
              : getResponses.length - 1];
  }

  static PushoverHttpResponse _ok() => PushoverHttpResponse(
    statusCode: 200,
    body: jsonEncode({'status': 1, 'request': 'req-1'}),
  );
}

PushoverHttpResponse _json(
  Map<String, Object?> body, {
  int statusCode = 200,
  Map<String, String> headers = const {},
}) => PushoverHttpResponse(
  statusCode: statusCode,
  body: jsonEncode(body),
  headers: headers,
);

PushoverClient _client(
  _FakeTransport transport, {
  String? device,
  String user = 'uQiRzpo4DXghDmr9QzzfQu27cmVRsG',
  PushoverFieldEncryptor? encryptor,
}) => PushoverClient(
  token: 'azGDORePK8gMaC0QOYAMyEEuzJnyUi',
  user: user,
  device: device,
  encryptor: encryptor,
  post: transport.post,
  get: transport.get,
  postMultipart: transport.postMultipart,
);

/// A 1x1 transparent GIF, small enough to inline and a real image type.
final Uint8List _gifBytes = base64.decode(
  'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
);

PushoverAttachment _attachment() =>
    PushoverAttachment(bytes: _gifBytes, mimeType: 'image/gif');

/// A deterministic IV source, so envelope bytes are reproducible in tests.
Random _fixedRandom() => Random(1);

const String _hexKey =
    '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';

void main() {
  group('PushoverClient.send', () {
    test('posts credentials and message fields', () async {
      final transport = _FakeTransport(
        postResponses: [
          _json(
            {'status': 1, 'request': 'req-42'},
            headers: {
              'x-limit-app-limit': '10000',
              'x-limit-app-remaining': '7496',
              'x-limit-app-reset': '1393653600',
            },
          ),
        ],
      );

      final result = await _client(transport).send(
        PushoverMessage(
          message: 'Build finished.',
          title: 'CI',
          priority: PushoverPriority.high,
          url: 'https://example.com/build/1',
          urlTitle: 'Open build',
          monospace: true,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            1393653600000,
            isUtc: true,
          ),
        ),
      );

      expect(
        transport.postUrls.single,
        Uri.parse('https://api.pushover.net/1/messages.json'),
      );
      expect(transport.postFields.single, {
        'token': 'azGDORePK8gMaC0QOYAMyEEuzJnyUi',
        'user': 'uQiRzpo4DXghDmr9QzzfQu27cmVRsG',
        'message': 'Build finished.',
        'title': 'CI',
        'priority': '1',
        'url': 'https://example.com/build/1',
        'url_title': 'Open build',
        'timestamp': '1393653600',
        'monospace': '1',
      });
      expect(result.request, 'req-42');
      expect(result.receipt, isNull);
      expect(result.limits?.remaining, 7496);
    });

    test('applies the client default device when none is given', () async {
      final transport = _FakeTransport();

      await _client(
        transport,
        device: 'phone',
      ).send(const PushoverMessage(message: 'hi'));

      expect(transport.postFields.single['device'], 'phone');
    });

    test('surfaces the errors array from a rejected request', () async {
      final transport = _FakeTransport(
        postResponses: [
          _json({
            'status': 0,
            'request': 'req-9',
            'errors': ['sound is invalid'],
          }, statusCode: 400),
        ],
      );

      await expectLater(
        _client(
          transport,
        ).send(const PushoverMessage(message: 'hi', sound: 'nope')),
        throwsA(
          isA<PushoverApiException>()
              .having((e) => e.errors, 'errors', ['sound is invalid'])
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.request, 'request', 'req-9'),
        ),
      );
    });

    test('returns the receipt for an emergency message', () async {
      final transport = _FakeTransport(
        postResponses: [
          _json({'status': 1, 'request': 'req-1', 'receipt': 'rcpt1'}),
        ],
      );

      final result = await _client(transport).send(
        const PushoverMessage(
          message: 'Server down.',
          priority: PushoverPriority.emergency,
          retry: 60,
          expire: 3600,
        ),
      );

      expect(result.receipt, 'rcpt1');
      expect(transport.postFields.single['priority'], '2');
      expect(transport.postFields.single['retry'], '60');
      expect(transport.postFields.single['expire'], '3600');
    });
  });

  group('PushoverMessage.validationError', () {
    test('accepts a well-formed message', () {
      expect(const PushoverMessage(message: 'hi').validationError, isNull);
    });

    test('rejects an over-long message rather than truncating it', () {
      final message = PushoverMessage(message: 'a' * 1025);

      expect(message.validationError, contains('1025 characters'));
    });

    test('rejects html and monospace together', () {
      const message = PushoverMessage(
        message: 'hi',
        html: true,
        monospace: true,
      );

      expect(message.validationError, contains('cannot both be enabled'));
    });

    test('requires retry and expire for emergency priority', () {
      const message = PushoverMessage(
        message: 'hi',
        priority: PushoverPriority.emergency,
      );

      expect(message.validationError, contains('requires both retry'));
    });

    test('enforces the retry floor and expiry ceiling', () {
      expect(
        const PushoverMessage(
          message: 'hi',
          priority: PushoverPriority.emergency,
          retry: 10,
          expire: 3600,
        ).validationError,
        contains('at least 30 seconds'),
      );
      expect(
        const PushoverMessage(
          message: 'hi',
          priority: PushoverPriority.emergency,
          retry: 60,
          expire: 20000,
        ).validationError,
        contains('between 1 and 10800'),
      );
    });

    test('rejects retry and expire outside emergency priority', () {
      const message = PushoverMessage(message: 'hi', retry: 60, expire: 3600);

      expect(message.validationError, contains('only to emergency priority'));
    });

    test('rejects an invalid device name', () {
      const message = PushoverMessage(message: 'hi', device: 'my phone!');

      expect(message.validationError, contains('may contain only letters'));
    });
  });

  group(sendPushoverNotificationToolName, () {
    test('sends the message and returns the request id', () async {
      final transport = _FakeTransport(
        postResponses: [
          _json({'status': 1, 'request': 'req-7'}),
        ],
      );
      final tool = createSendPushoverNotificationTool(
        client: _client(transport),
      );

      final result = await tool.invoke(
        AIFunctionArguments({'message': 'Deploy finished.', 'title': 'CI'}),
      );

      expect(result, {'request': 'req-7'});
      expect(transport.postFields.single['message'], 'Deploy finished.');
      expect(transport.postFields.single['title'], 'CI');
    });

    test('does not expose the recipient or token as arguments', () {
      final tool = createSendPushoverNotificationTool(
        client: _client(_FakeTransport()),
      );
      final properties =
          (tool.parametersSchema as Map)['properties'] as Map<String, Object?>;

      expect(properties.keys, isNot(contains('user')));
      expect(properties.keys, isNot(contains('token')));
      expect(properties.keys, isNot(contains('device')));
      expect((tool.parametersSchema as Map)['required'], ['message']);
    });

    test('omits emergency priority unless it is allowed', () {
      final tool = createSendPushoverNotificationTool(
        client: _client(_FakeTransport()),
      );
      final properties =
          (tool.parametersSchema as Map)['properties'] as Map<String, Object?>;
      final priority = properties['priority']! as Map<String, Object?>;

      expect(priority['enum'], [-2, -1, 0, 1]);
      expect(properties.keys, isNot(contains('retry')));
      expect(properties.keys, isNot(contains('expire')));
    });

    test('declares emergency arguments when it is allowed', () {
      final tool = createSendPushoverNotificationTool(
        client: _client(_FakeTransport()),
        allowEmergencyPriority: true,
        allowDeviceTargeting: true,
      );
      final properties =
          (tool.parametersSchema as Map)['properties'] as Map<String, Object?>;
      final priority = properties['priority']! as Map<String, Object?>;

      expect(priority['enum'], [-2, -1, 0, 1, 2]);
      expect(properties.keys, containsAll(['retry', 'expire', 'device']));
    });

    test('refuses an emergency priority the tool does not allow', () async {
      final transport = _FakeTransport();
      final tool = createSendPushoverNotificationTool(
        client: _client(transport),
      );

      final result = await tool.invoke(
        AIFunctionArguments({'message': 'hi', 'priority': 2}),
      );

      expect(result, contains('priority must be one of -2, -1, 0, 1'));
      expect(transport.postUrls, isEmpty);
    });

    test('ignores a device argument when targeting is off', () async {
      final transport = _FakeTransport();
      final tool = createSendPushoverNotificationTool(
        client: _client(transport),
      );

      await tool.invoke(
        AIFunctionArguments({'message': 'hi', 'device': 'phone'}),
      );

      expect(transport.postFields.single.containsKey('device'), isFalse);
    });

    test('reports a validation failure without calling the API', () async {
      final transport = _FakeTransport();
      final tool = createSendPushoverNotificationTool(
        client: _client(transport),
      );

      final result = await tool.invoke(
        AIFunctionArguments({'message': 'a' * 2000}),
      );

      expect(result, contains('the limit is 1024'));
      expect(transport.postUrls, isEmpty);
    });

    test('reports a missing message', () async {
      final tool = createSendPushoverNotificationTool(
        client: _client(_FakeTransport()),
      );

      final result = await tool.invoke(AIFunctionArguments({}));

      expect(result, contains('message is required'));
    });

    test('returns Pushover\'s wording instead of throwing', () async {
      final transport = _FakeTransport(
        postResponses: [
          _json({
            'status': 0,
            'request': 'req-3',
            'errors': ['application token is invalid'],
          }, statusCode: 400),
        ],
      );
      final tool = createSendPushoverNotificationTool(
        client: _client(transport),
      );

      final result = await tool.invoke(AIFunctionArguments({'message': 'hi'}));

      expect(result, contains('application token is invalid'));
    });

    test('accepts a stringified integer priority', () async {
      final transport = _FakeTransport();
      final tool = createSendPushoverNotificationTool(
        client: _client(transport),
      );

      await tool.invoke(
        AIFunctionArguments({'message': 'hi', 'priority': '-1'}),
      );

      expect(transport.postFields.single['priority'], '-1');
    });
  });

  group(pushoverLimitsToolName, () {
    test('reports the remaining quota', () async {
      final transport = _FakeTransport(
        getResponses: [
          _json({
            'status': 1,
            'request': 'req-1',
            'limit': 10000,
            'remaining': 7496,
            'reset': 1393653600,
          }),
        ],
      );
      final tool = createPushoverLimitsTool(client: _client(transport));

      final result = await tool.invoke(AIFunctionArguments({}));

      expect(result, {
        'limit': 10000,
        'remaining': 7496,
        'resetsAt': '2014-03-01T06:00:00.000Z',
      });
      expect(transport.getUrls.single.path, '/1/apps/limits.json');
    });
  });

  group(pushoverReceiptToolName, () {
    test('reports an acknowledged receipt', () async {
      final transport = _FakeTransport(
        getResponses: [
          _json({
            'status': 1,
            'request': 'req-1',
            'acknowledged': 1,
            'acknowledged_at': 1393653600,
            'acknowledged_by': 'uQiRzpo4DXghDmr9QzzfQu27cmVRsG',
            'expired': 0,
          }),
        ],
      );
      final tool = createPushoverReceiptTool(client: _client(transport));

      final result = await tool.invoke(
        AIFunctionArguments({'receipt': 'rcpt1'}),
      );

      expect(result, isA<Map<String, Object?>>());
      expect((result! as Map)['acknowledged'], isTrue);
      expect((result as Map)['expired'], isFalse);
      expect(transport.getUrls.single.path, '/1/receipts/rcpt1.json');
    });

    test('cancels retries when asked', () async {
      final transport = _FakeTransport();
      final tool = createPushoverReceiptTool(client: _client(transport));

      final result = await tool.invoke(
        AIFunctionArguments({'receipt': 'rcpt1', 'cancel': true}),
      );

      expect(result, contains('Cancelled'));
      expect(transport.postUrls.single.path, '/1/receipts/rcpt1/cancel.json');
    });

    test('refuses a receipt id that would rewrite the request path', () async {
      final transport = _FakeTransport();
      final tool = createPushoverReceiptTool(client: _client(transport));

      final result = await tool.invoke(
        AIFunctionArguments({'receipt': 'rcpt/../apps/limits'}),
      );

      expect(result, contains('not valid'));
      expect(transport.getUrls, isEmpty);
      expect(transport.postUrls, isEmpty);
    });

    test('refuses a receipt id carrying a query separator', () async {
      final transport = _FakeTransport();
      final tool = createPushoverReceiptTool(client: _client(transport));

      final result = await tool.invoke(
        AIFunctionArguments({'receipt': 'rcpt1?user=someone', 'cancel': true}),
      );

      expect(result, contains('not valid'));
      expect(transport.postUrls, isEmpty);
    });
  });

  group('PushoverClient auxiliary endpoints', () {
    test('validates a user key', () async {
      final transport = _FakeTransport(
        postResponses: [
          _json({
            'status': 1,
            'request': 'req-1',
            'group': 0,
            'devices': ['phone', 'tablet'],
            'licenses': ['iOS'],
          }),
        ],
      );

      final validation = await _client(transport).validateUser();

      expect(validation.isGroup, isFalse);
      expect(validation.devices, ['phone', 'tablet']);
      expect(validation.licenses, ['iOS']);
    });

    test('lists sounds', () async {
      final transport = _FakeTransport(
        getResponses: [
          _json({
            'status': 1,
            'request': 'req-1',
            'sounds': {'pushover': 'Pushover (default)', 'magic': 'Magic'},
          }),
        ],
      );

      final sounds = await _client(transport).fetchSounds();

      expect(sounds, {'pushover': 'Pushover (default)', 'magic': 'Magic'});
    });

    test('rejects a malformed body', () async {
      final transport = _FakeTransport(
        getResponses: [
          const PushoverHttpResponse(statusCode: 502, body: '<html>oops'),
        ],
      );

      await expectLater(
        _client(transport).fetchLimits(),
        throwsA(
          isA<PushoverApiException>().having(
            (e) => e.message,
            'message',
            contains('malformed response'),
          ),
        ),
      );
    });
  });

  group('attachments', () {
    test('sends an attachment as multipart alongside the fields', () async {
      final transport = _FakeTransport();

      await _client(transport).send(
        PushoverMessage(
          message: 'Here is the chart.',
          attachment: _attachment(),
        ),
      );

      expect(transport.attachments.single.bytes, _gifBytes);
      expect(transport.attachments.single.mimeType, 'image/gif');
      expect(transport.postFields.single['message'], 'Here is the chart.');
    });

    test('uses the form-encoded path when there is no attachment', () async {
      final transport = _FakeTransport();

      await _client(transport).send(const PushoverMessage(message: 'hi'));

      expect(transport.attachments, isEmpty);
      expect(transport.postUrls, hasLength(1));
    });

    test('rejects an attachment over the size limit', () {
      final message = PushoverMessage(
        message: 'hi',
        attachment: PushoverAttachment(
          bytes: Uint8List(pushoverMaxAttachmentBytes + 1),
          mimeType: 'image/jpeg',
        ),
      );

      expect(message.validationError, contains('the limit is 5242880'));
    });

    test('rejects an empty attachment and a bogus MIME type', () {
      expect(
        PushoverMessage(
          message: 'hi',
          attachment: PushoverAttachment(
            bytes: Uint8List(0),
            mimeType: 'image/png',
          ),
        ).validationError,
        contains('attachment is empty'),
      );
      expect(
        PushoverMessage(
          message: 'hi',
          attachment: PushoverAttachment(bytes: _gifBytes, mimeType: 'jpeg'),
        ).validationError,
        contains('is not a MIME type'),
      );
    });

    test('does not reach the network when an attachment is invalid', () async {
      final transport = _FakeTransport();

      await expectLater(
        _client(transport).send(
          PushoverMessage(
            message: 'hi',
            attachment: PushoverAttachment(
              bytes: Uint8List(pushoverMaxAttachmentBytes + 1),
              mimeType: 'image/jpeg',
            ),
          ),
        ),
        throwsA(isA<PushoverApiException>()),
      );
      expect(transport.postUrls, isEmpty);
      expect(transport.attachments, isEmpty);
    });

    test('resolves a model-supplied reference through the host', () async {
      final transport = _FakeTransport();
      final requested = <String>[];
      final tool = createSendPushoverNotificationTool(
        client: _client(transport),
        attachmentResolver: (reference) async {
          requested.add(reference);
          return _attachment();
        },
      );

      await tool.invoke(
        AIFunctionArguments({'message': 'chart', 'attachment': 'chart.gif'}),
      );

      expect(requested, ['chart.gif']);
      expect(transport.attachments, hasLength(1));
    });

    test('omits the attachment argument without a resolver', () {
      final tool = createSendPushoverNotificationTool(
        client: _client(_FakeTransport()),
      );
      final properties =
          (tool.parametersSchema as Map)['properties'] as Map<String, Object?>;

      expect(properties.keys, isNot(contains('attachment')));
    });

    test('reports an unresolvable reference to the model', () async {
      final transport = _FakeTransport();
      final tool = createSendPushoverNotificationTool(
        client: _client(transport),
        attachmentResolver: (_) async => null,
      );

      final result = await tool.invoke(
        AIFunctionArguments({'message': 'chart', 'attachment': 'missing.png'}),
      );

      expect(result, contains('no attachment found for "missing.png"'));
      expect(transport.postUrls, isEmpty);
    });

    test('reports a resolver that throws to the model', () async {
      final transport = _FakeTransport();
      final tool = createSendPushoverNotificationTool(
        client: _client(transport),
        attachmentResolver: (_) async => throw StateError('outside the folder'),
      );

      final result = await tool.invoke(
        AIFunctionArguments({
          'message': 'chart',
          'attachment': '../secret.png',
        }),
      );

      expect(result, contains('outside the folder'));
      expect(transport.postUrls, isEmpty);
    });
  });

  group('PushoverAesEncryptor', () {
    test('round-trips a field', () {
      final encryptor = PushoverAesEncryptor.fromHexKey(
        _hexKey,
        random: _fixedRandom(),
      );

      final envelope = encryptor('Disk almost full on the build box.');

      expect(envelope, isNot(contains('Disk')));
      expect(encryptor.decrypt(envelope), 'Disk almost full on the build box.');
    });

    test('round-trips text that needs more than one AES block', () {
      final encryptor = PushoverAesEncryptor.fromHexKey(
        _hexKey,
        random: _fixedRandom(),
      );
      final plaintext = 'The quick brown fox. ' * 40;

      expect(encryptor.decrypt(encryptor(plaintext)), plaintext);
    });

    test('round-trips non-ASCII text', () {
      final encryptor = PushoverAesEncryptor.fromHexKey(
        _hexKey,
        random: _fixedRandom(),
      );

      expect(encryptor.decrypt(encryptor('温度 25°C — 完了 ✅')), '温度 25°C — 完了 ✅');
    });

    test('produces a fresh IV per call', () {
      final encryptor = PushoverAesEncryptor.fromHexKey(_hexKey);

      expect(encryptor('same text'), isNot(encryptor('same text')));
    });

    test('lays out the envelope as iv, ciphertext, then mac', () {
      final encryptor = PushoverAesEncryptor.fromHexKey(
        _hexKey,
        random: _fixedRandom(),
      );

      final bytes = base64.decode(encryptor('hi'));

      // AES-CBC emits whole blocks, so the ciphertext is a multiple of 16.
      final ciphertextLength =
          bytes.length -
          pushoverEncryptionIvLength -
          pushoverEncryptionMacLength;
      expect(ciphertextLength % 16, 0);
      expect(ciphertextLength, greaterThan(0));
    });

    test('refuses a tampered envelope', () {
      final encryptor = PushoverAesEncryptor.fromHexKey(
        _hexKey,
        random: _fixedRandom(),
      );
      final bytes = base64.decode(encryptor('hi'))
        ..[pushoverEncryptionIvLength] ^= 0xff;

      expect(
        () => encryptor.decrypt(base64.encode(bytes)),
        throwsA(
          isA<PushoverApiException>().having(
            (e) => e.message,
            'message',
            contains('failed authentication'),
          ),
        ),
      );
    });

    test('refuses a envelope encrypted under a different key', () {
      final sender = PushoverAesEncryptor.fromHexKey(_hexKey);
      final other = PushoverAesEncryptor.fromHexKey('ff' * 32);

      expect(
        () => other.decrypt(sender('hi')),
        throwsA(isA<PushoverApiException>()),
      );
    });

    test('rejects a key of the wrong length or alphabet', () {
      expect(
        () => PushoverAesEncryptor.fromHexKey('abc'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => PushoverAesEncryptor.fromHexKey('z' * 64),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => PushoverAesEncryptor(Uint8List(16)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts an uppercase key', () {
      expect(
        PushoverAesEncryptor.fromHexKey(_hexKey.toUpperCase()).key,
        PushoverAesEncryptor.fromHexKey(_hexKey).key,
      );
    });
  });

  group('encrypted messages', () {
    test('encrypts only the protected fields', () async {
      final transport = _FakeTransport();
      final encryptor = PushoverAesEncryptor.fromHexKey(_hexKey);

      await _client(transport, encryptor: encryptor.call).send(
        const PushoverMessage(
          message: 'Secret body',
          title: 'Secret title',
          url: 'https://example.com/secret',
          urlTitle: 'Open it',
          sound: 'magic',
          priority: PushoverPriority.high,
          encrypt: true,
        ),
      );

      final fields = transport.postFields.single;
      expect(fields['encrypted'], '1');
      expect(encryptor.decrypt(fields['message']!), 'Secret body');
      expect(encryptor.decrypt(fields['title']!), 'Secret title');
      expect(encryptor.decrypt(fields['url']!), 'https://example.com/secret');
      expect(encryptor.decrypt(fields['url_title']!), 'Open it');
      // Pushover's servers act on these, so they must stay readable.
      expect(fields['sound'], 'magic');
      expect(fields['priority'], '1');
    });

    test('leaves fields alone when encrypt is not set', () async {
      final transport = _FakeTransport();

      await _client(
        transport,
        encryptor: PushoverAesEncryptor.fromHexKey(_hexKey).call,
      ).send(const PushoverMessage(message: 'Plain body'));

      expect(transport.postFields.single['message'], 'Plain body');
      expect(transport.postFields.single.containsKey('encrypted'), isFalse);
    });

    test('refuses to send when no encryptor is configured', () async {
      final transport = _FakeTransport();

      await expectLater(
        _client(
          transport,
        ).send(const PushoverMessage(message: 'Secret', encrypt: true)),
        throwsA(
          isA<PushoverApiException>().having(
            (e) => e.message,
            'message',
            contains('no encryptor'),
          ),
        ),
      );
      expect(transport.postUrls, isEmpty);
    });

    test('sends envelopes longer than the plaintext limits', () async {
      final transport = _FakeTransport();
      final encryptor = PushoverAesEncryptor.fromHexKey(_hexKey);

      // The envelope floor is 108 base64 characters, so an encrypted
      // url_title can never fit its own 100-character limit. Validating the
      // envelope instead of the plaintext would make this unsendable; only
      // Pushover gets to reject it.
      await _client(transport, encryptor: encryptor.call).send(
        const PushoverMessage(
          message: 'hi',
          url: 'https://example.com',
          urlTitle: 'Open',
          encrypt: true,
        ),
      );

      final fields = transport.postFields.single;
      expect(
        fields['url_title']!.length,
        greaterThan(pushoverMaxUrlTitleLength),
      );
      expect(encryptor.decrypt(fields['url_title']!), 'Open');
    });

    test('the tool encrypts when told to', () async {
      final transport = _FakeTransport();
      final encryptor = PushoverAesEncryptor.fromHexKey(_hexKey);
      final tool = createSendPushoverNotificationTool(
        client: _client(transport, encryptor: encryptor.call),
        encryptByDefault: true,
      );

      await tool.invoke(
        AIFunctionArguments({'message': 'Secret from a model'}),
      );

      final fields = transport.postFields.single;
      expect(fields['encrypted'], '1');
      expect(encryptor.decrypt(fields['message']!), 'Secret from a model');
    });
  });

  group('addPushover', () {
    test('registers the send and limits tools', () {
      final services = ServiceCollection()
        ..addPushover(
          token: 'azGDORePK8gMaC0QOYAMyEEuzJnyUi',
          user: 'uQiRzpo4DXghDmr9QzzfQu27cmVRsG',
        );

      final tools = services.buildServiceProvider().getServices<AITool>();

      expect(tools.map((tool) => tool.name), [
        sendPushoverNotificationToolName,
        pushoverLimitsToolName,
      ]);
    });

    test('registers the receipt tool with emergency priority', () {
      final services = ServiceCollection()
        ..addPushover(
          token: 'azGDORePK8gMaC0QOYAMyEEuzJnyUi',
          user: 'uQiRzpo4DXghDmr9QzzfQu27cmVRsG',
          allowEmergencyPriority: true,
        );

      final tools = services.buildServiceProvider().getServices<AITool>();

      expect(tools.map((tool) => tool.name), contains(pushoverReceiptToolName));
    });

    test('preserves a client registered beforehand', () async {
      final transport = _FakeTransport();
      final services = ServiceCollection()
        ..addSingleton<PushoverClient>((_) => _client(transport))
        ..addPushover(includeLimitsTool: false);

      final tools = services.buildServiceProvider().getServices<AITool>();
      await (tools.single as AIFunction).invoke(
        AIFunctionArguments({'message': 'hi'}),
      );

      expect(transport.postFields.single['message'], 'hi');
    });

    test('rejects registration with no credentials and no client', () {
      expect(
        () => ServiceCollection().addPushover(),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

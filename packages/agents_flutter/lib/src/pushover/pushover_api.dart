import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'pushover_encryption.dart';

/// The root of the Pushover REST API, without a trailing slash.
///
/// See https://pushover.net/api.
const String pushoverApiBaseUrl = 'https://api.pushover.net/1';

/// The maximum length, in UTF-8 characters, of a message body.
const int pushoverMaxMessageLength = 1024;

/// The maximum length of a message title.
const int pushoverMaxTitleLength = 250;

/// The maximum length of a supplementary URL.
const int pushoverMaxUrlLength = 512;

/// The maximum length of a supplementary URL's title.
const int pushoverMaxUrlTitleLength = 100;

/// The maximum length of a device name.
const int pushoverMaxDeviceNameLength = 25;

/// The shortest retry interval, in seconds, accepted for emergency messages.
const int pushoverMinRetrySeconds = 30;

/// The longest expiry, in seconds, accepted for emergency messages.
const int pushoverMaxExpireSeconds = 10800;

/// The maximum size, in bytes, of a message attachment.
const int pushoverMaxAttachmentBytes = 5242880;

/// An HTTP response reduced to what the Pushover client needs.
///
/// Pushover reports input problems as a 4xx whose *body* carries the
/// human-readable reason, so the transport must hand back the status and body
/// together rather than throwing on a non-200 the way a plain "fetch the body"
/// helper would. [headers] carries the `X-Limit-App-*` quota headers.
final class PushoverHttpResponse {
  /// Creates a response.
  const PushoverHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });

  /// The HTTP status code.
  final int statusCode;

  /// The raw response body.
  final String body;

  /// The response headers, lower-cased by the transport.
  final Map<String, String> headers;
}

/// Posts form-encoded [fields] and returns the raw response.
///
/// Implementations must not throw on a 4xx; only transport failures should
/// propagate. Wrapping the call in a function type keeps `package:http` out of
/// [PushoverClient]'s logic so tests can inject canned responses.
typedef PushoverHttpPost =
    Future<PushoverHttpResponse> Function(Uri url, Map<String, String> fields);

/// Performs a GET and returns the raw response.
typedef PushoverHttpGet = Future<PushoverHttpResponse> Function(Uri url);

/// Posts [fields] and [attachment] as `multipart/form-data`.
///
/// Pushover also accepts a base64 attachment field, but documents it as a
/// workaround for HTTP libraries without multipart support; `package:http` has
/// it, and base64 would inflate the payload by roughly 35% against a 5 MiB
/// ceiling.
typedef PushoverHttpPostMultipart =
    Future<PushoverHttpResponse> Function(
      Uri url,
      Map<String, String> fields,
      PushoverAttachment attachment,
    );

/// The default [PushoverHttpPost], backed by `package:http`.
Future<PushoverHttpResponse> pushoverHttpPost(
  Uri url,
  Map<String, String> fields,
) async {
  final response = await http.post(url, body: fields);
  return _toPushoverResponse(response);
}

/// The default [PushoverHttpGet], backed by `package:http`.
Future<PushoverHttpResponse> pushoverHttpGet(Uri url) async {
  final response = await http.get(url);
  return _toPushoverResponse(response);
}

/// The default [PushoverHttpPostMultipart], backed by `package:http`.
Future<PushoverHttpResponse> pushoverHttpPostMultipart(
  Uri url,
  Map<String, String> fields,
  PushoverAttachment attachment,
) async {
  final request = http.MultipartRequest('POST', url)
    ..fields.addAll(fields)
    ..files.add(
      http.MultipartFile.fromBytes(
        'attachment',
        attachment.bytes,
        filename: attachment.filename,
        contentType: MediaType.parse(attachment.mimeType),
      ),
    );
  final response = await http.Response.fromStream(await request.send());
  return _toPushoverResponse(response);
}

PushoverHttpResponse _toPushoverResponse(http.Response response) =>
    PushoverHttpResponse(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers,
    );

/// Thrown when Pushover rejects a request or returns a malformed response.
final class PushoverApiException implements Exception {
  /// Creates an exception with a human-readable [message].
  const PushoverApiException(
    this.message, {
    this.statusCode,
    this.errors = const [],
    this.request,
  });

  /// A description of what went wrong.
  final String message;

  /// The HTTP status code, when the failure came from a response.
  final int? statusCode;

  /// The `errors` array Pushover returns alongside `status: 0`.
  ///
  /// These strings are written for humans ("message cannot be blank"), so they
  /// are worth surfacing verbatim to whoever — or whatever — built the request.
  final List<String> errors;

  /// The request identifier Pushover assigns to every API call.
  final String? request;

  @override
  String toString() {
    final buffer = StringBuffer('PushoverApiException: $message');
    if (errors.isNotEmpty) buffer.write(' (${errors.join('; ')})');
    return buffer.toString();
  }
}

/// How urgently a message is delivered.
///
/// See https://pushover.net/api#priority.
enum PushoverPriority {
  /// No notification is generated; iOS increments the badge only.
  lowest(-2),

  /// A notification without sound or vibration.
  low(-1),

  /// The default: sound and vibration per the device's own settings.
  normal(0),

  /// Bypasses the user's quiet hours and always alerts.
  high(1),

  /// Repeats until the user acknowledges it. Requires `retry` and `expire`.
  emergency(2);

  const PushoverPriority(this.value);

  /// The wire value sent as the `priority` field.
  final int value;

  /// The priority matching [value], or null if no priority uses it.
  static PushoverPriority? fromValue(int value) {
    for (final priority in PushoverPriority.values) {
      if (priority.value == value) return priority;
    }
    return null;
  }
}

/// An image attached to a notification.
///
/// Pushover allows one attachment per message and caps it at
/// [pushoverMaxAttachmentBytes]; resizing is the sender's job. The recipient's
/// device downloads the image, after which Pushover deletes its copy. Clients
/// older than app version 3.0 discard attachments silently, so a message can
/// arrive without its image for reasons that have nothing to do with the
/// request.
final class PushoverAttachment {
  /// Creates an attachment from raw [bytes] of type [mimeType].
  const PushoverAttachment({
    required this.bytes,
    required this.mimeType,
    this.filename = 'attachment',
  });

  /// The image data.
  final Uint8List bytes;

  /// The image's MIME type, such as `image/jpeg`.
  final String mimeType;

  /// The filename reported in the multipart body.
  final String filename;

  /// Describes why Pushover would reject this attachment, or null when it is
  /// well-formed.
  String? get validationError {
    if (bytes.isEmpty) return 'attachment is empty.';
    if (bytes.length > pushoverMaxAttachmentBytes) {
      return 'attachment is ${bytes.length} bytes; the limit is '
          '$pushoverMaxAttachmentBytes. Resize the image before sending.';
    }
    if (!RegExp(r'^[\w.+-]+/[\w.+-]+$').hasMatch(mimeType)) {
      return 'attachment mimeType "$mimeType" is not a MIME type such as '
          'image/jpeg.';
    }
    if (filename.trim().isEmpty) return 'attachment filename is empty.';
    return null;
  }
}

/// A notification to deliver through Pushover.
final class PushoverMessage {
  /// Creates a message.
  const PushoverMessage({
    required this.message,
    this.title,
    this.priority = PushoverPriority.normal,
    this.sound,
    this.url,
    this.urlTitle,
    this.device,
    this.timestamp,
    this.ttl,
    this.html = false,
    this.monospace = false,
    this.retry,
    this.expire,
    this.tags,
    this.attachment,
    this.encrypt = false,
  });

  /// The message body.
  final String message;

  /// An optional title; Pushover falls back to the application's name.
  final String? title;

  /// How urgently the message is delivered.
  final PushoverPriority priority;

  /// The name of a built-in or user-uploaded sound.
  final String? sound;

  /// A supplementary URL shown with the message.
  final String? url;

  /// The label for [url].
  final String? urlTitle;

  /// A comma-separated list of the recipient's own device names.
  ///
  /// When null the message goes to all of the recipient's devices.
  final String? device;

  /// The time to display for the message, instead of the time it arrived.
  final DateTime? timestamp;

  /// How long, in seconds, the message survives before auto-deleting.
  ///
  /// Ignored by Pushover for [PushoverPriority.emergency].
  final int? ttl;

  /// Whether [message] contains Pushover's supported HTML subset.
  ///
  /// Mutually exclusive with [monospace].
  final bool html;

  /// Whether [message] renders in a monospace font.
  ///
  /// Mutually exclusive with [html].
  final bool monospace;

  /// How often, in seconds, an emergency message repeats. Minimum 30.
  final int? retry;

  /// How long, in seconds, an emergency message keeps retrying. Maximum 10800.
  final int? expire;

  /// Comma-separated tags stored with an emergency message's receipt.
  final String? tags;

  /// An image to deliver alongside the message.
  final PushoverAttachment? attachment;

  /// Whether to encrypt [message], [title], [url], and [urlTitle]
  /// end-to-end.
  ///
  /// Requires the sending [PushoverClient] to hold a
  /// [PushoverFieldEncryptor]; the recipient's device must have the matching
  /// key configured or the notification arrives unreadable.
  ///
  /// Envelopes are longer than their plaintext — a gzip header, one whole AES
  /// block, a 16-byte IV, and a 32-byte MAC put the floor at 108 base64
  /// characters however short the input. So an encrypted field can exceed the
  /// plaintext limits this class validates, and [urlTitle] cannot fit its
  /// 100-character limit at all. Length checks therefore run against the
  /// plaintext, which is what the recipient reads. Verified against the live
  /// API: it accepts an encrypted `url_title` well past 100 characters, so it
  /// does not measure envelopes. Do not add a post-encryption length check —
  /// it makes an encrypted [urlTitle] impossible to send.
  final bool encrypt;

  /// Describes the first problem that would make Pushover reject this message,
  /// or null when it is well-formed.
  ///
  /// Checked locally so a malformed request costs a round trip and, more to the
  /// point, so the caller gets a reason more specific than the API's.
  String? get validationError {
    if (message.trim().isEmpty) return 'message cannot be empty.';
    if (message.length > pushoverMaxMessageLength) {
      return 'message is ${message.length} characters; the limit is '
          '$pushoverMaxMessageLength.';
    }
    if ((title?.length ?? 0) > pushoverMaxTitleLength) {
      return 'title is ${title!.length} characters; the limit is '
          '$pushoverMaxTitleLength.';
    }
    if ((url?.length ?? 0) > pushoverMaxUrlLength) {
      return 'url is ${url!.length} characters; the limit is '
          '$pushoverMaxUrlLength.';
    }
    if ((urlTitle?.length ?? 0) > pushoverMaxUrlTitleLength) {
      return 'urlTitle is ${urlTitle!.length} characters; the limit is '
          '$pushoverMaxUrlTitleLength.';
    }
    if (urlTitle != null && (url == null || url!.isEmpty)) {
      return 'urlTitle requires url.';
    }
    final deviceError = _deviceValidationError;
    if (deviceError != null) return deviceError;
    final attachmentError = attachment?.validationError;
    if (attachmentError != null) return attachmentError;
    if (html && monospace) {
      return 'html and monospace cannot both be enabled.';
    }
    if (ttl != null && ttl! <= 0) {
      return 'ttl must be a positive number of seconds.';
    }

    if (priority == PushoverPriority.emergency) {
      if (retry == null || expire == null) {
        return 'emergency priority requires both retry and expire.';
      }
      if (retry! < pushoverMinRetrySeconds) {
        return 'retry must be at least $pushoverMinRetrySeconds seconds.';
      }
      if (expire! <= 0 || expire! > pushoverMaxExpireSeconds) {
        return 'expire must be between 1 and $pushoverMaxExpireSeconds '
            'seconds.';
      }
    } else if (retry != null || expire != null || tags != null) {
      return 'retry, expire, and tags apply only to emergency priority.';
    }
    return null;
  }

  String? get _deviceValidationError {
    final names = device;
    if (names == null || names.isEmpty) return null;
    for (final name in names.split(',')) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) return 'device contains an empty name.';
      if (trimmed.length > pushoverMaxDeviceNameLength) {
        return 'device name "$trimmed" exceeds '
            '$pushoverMaxDeviceNameLength characters.';
      }
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(trimmed)) {
        return 'device name "$trimmed" may contain only letters, numbers, '
            'underscores, and hyphens.';
      }
    }
    return null;
  }

  /// The form fields for this message, excluding the `token` and `user`
  /// credentials the client supplies.
  ///
  /// When [encrypt] is set, [encryptor] is applied to each protected field and
  /// `encrypted=1` is added. Routing fields are left alone: Pushover's servers
  /// act on `sound`, `device`, `priority`, and the emergency parameters, so
  /// encrypting them would break delivery.
  Map<String, String> toFields({PushoverFieldEncryptor? encryptor}) {
    String? protect(String? value) {
      if (value == null) return null;
      return encrypt && encryptor != null ? encryptor(value) : value;
    }

    return {
      'message': protect(message)!,
      'title': ?protect(title),
      if (priority != PushoverPriority.normal)
        'priority': priority.value.toString(),
      'sound': ?sound,
      'url': ?protect(url),
      'url_title': ?protect(urlTitle),
      'device': ?device,
      if (timestamp != null)
        'timestamp': (timestamp!.millisecondsSinceEpoch ~/ 1000).toString(),
      if (ttl != null) 'ttl': ttl!.toString(),
      if (html) 'html': '1',
      if (monospace) 'monospace': '1',
      if (retry != null) 'retry': retry!.toString(),
      if (expire != null) 'expire': expire!.toString(),
      'tags': ?tags,
      if (encrypt) 'encrypted': '1',
    };
  }
}

/// The outcome of a successful send.
final class PushoverMessageResult {
  /// Creates a result.
  const PushoverMessageResult({
    required this.request,
    this.receipt,
    this.limits,
  });

  /// The request identifier Pushover assigned.
  final String request;

  /// The receipt identifier, present only for emergency-priority messages.
  final String? receipt;

  /// The monthly quota reported in the response headers, when present.
  final PushoverLimits? limits;

  /// This result as a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'request': request,
    if (receipt != null) 'receipt': receipt,
    if (limits != null) 'messagesRemaining': limits!.remaining,
  };
}

/// An application's monthly message quota.
final class PushoverLimits {
  /// Creates a quota snapshot.
  const PushoverLimits({
    required this.limit,
    required this.remaining,
    required this.reset,
  });

  /// The number of messages the application may send per month.
  final int limit;

  /// The number of messages remaining in the current period.
  final int remaining;

  /// When the quota resets, or null when the API did not report it.
  final DateTime? reset;

  /// This quota as a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'limit': limit,
    'remaining': remaining,
    if (reset != null) 'resetsAt': reset!.toUtc().toIso8601String(),
  };
}

/// The result of validating a user or group key.
final class PushoverValidation {
  /// Creates a validation result.
  const PushoverValidation({
    required this.isGroup,
    required this.devices,
    required this.licenses,
  });

  /// Whether the key identifies a delivery group rather than a single user.
  final bool isGroup;

  /// The names of the user's registered devices.
  final List<String> devices;

  /// The platforms the user is licensed on, such as `Android` or `iOS`.
  final List<String> licenses;

  /// This result as a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'isGroup': isGroup,
    'devices': devices,
    'licenses': licenses,
  };
}

/// The delivery state of an emergency-priority message.
final class PushoverReceipt {
  /// Creates a receipt.
  const PushoverReceipt({
    required this.acknowledged,
    required this.expired,
    this.acknowledgedAt,
    this.acknowledgedBy,
    this.acknowledgedByDevice,
    this.lastDeliveredAt,
    this.expiresAt,
  });

  /// Whether a recipient has acknowledged the message.
  final bool acknowledged;

  /// Whether the retry window has closed.
  final bool expired;

  /// When the message was acknowledged.
  final DateTime? acknowledgedAt;

  /// The user key that acknowledged the message.
  final String? acknowledgedBy;

  /// The device that acknowledged the message.
  final String? acknowledgedByDevice;

  /// When the message was last re-delivered.
  final DateTime? lastDeliveredAt;

  /// When retries stop.
  final DateTime? expiresAt;

  /// This receipt as a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'acknowledged': acknowledged,
    'expired': expired,
    if (acknowledgedAt != null)
      'acknowledgedAt': acknowledgedAt!.toUtc().toIso8601String(),
    if (acknowledgedBy != null) 'acknowledgedBy': acknowledgedBy,
    if (acknowledgedByDevice != null)
      'acknowledgedByDevice': acknowledgedByDevice,
    if (lastDeliveredAt != null)
      'lastDeliveredAt': lastDeliveredAt!.toUtc().toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
  };
}

/// A client for the Pushover REST API.
///
/// The application [token] and the recipient [user] key are supplied when the
/// client is constructed, never per call: they are credentials, and the tools
/// built on this client must not let a model choose who gets notified.
final class PushoverClient {
  /// Creates a client that sends as [token] to [user].
  ///
  /// [user] may be a user key, a group key, or up to 50 comma-separated user
  /// keys. [device] restricts every message to the named devices unless a
  /// message overrides it.
  PushoverClient({
    required this.token,
    required this.user,
    this.device,
    this.encryptor,
    PushoverHttpPost? post,
    PushoverHttpGet? get,
    PushoverHttpPostMultipart? postMultipart,
    this.baseUrl = pushoverApiBaseUrl,
  }) : _post = post ?? pushoverHttpPost,
       _get = get ?? pushoverHttpGet,
       _postMultipart = postMultipart ?? pushoverHttpPostMultipart;

  /// The application's API token.
  final String token;

  /// The recipient's user or group key.
  final String user;

  /// The default device restriction, if any.
  final String? device;

  final PushoverHttpPost _post;
  final PushoverHttpGet _get;
  final PushoverHttpPostMultipart _postMultipart;

  /// Encrypts protected fields when a message asks for it.
  final PushoverFieldEncryptor? encryptor;

  /// The API root this client talks to, overridable for tests.
  final String baseUrl;

  /// Sends [message] and returns its request identifier.
  ///
  /// A message carrying an attachment goes out as `multipart/form-data`;
  /// everything else is form-encoded.
  ///
  /// Throws a [PushoverApiException] when the message is malformed or Pushover
  /// rejects it.
  Future<PushoverMessageResult> send(PushoverMessage message) async {
    final error = message.validationError;
    if (error != null) {
      throw PushoverApiException(error, errors: [error]);
    }
    if (message.encrypt && encryptor == null) {
      throw const PushoverApiException(
        'This message asks to be encrypted, but the client has no encryptor. '
        'Construct PushoverClient with an encryptor holding the recipient\'s '
        '256-bit key.',
      );
    }

    final fields = {
      'token': token,
      'user': user,
      ...message.toFields(encryptor: encryptor),
      if (message.device == null && device != null) 'device': device!,
    };
    final url = Uri.parse('$baseUrl/messages.json');
    final attachment = message.attachment;
    final response = attachment == null
        ? await _post(url, fields)
        : await _postMultipart(url, fields, attachment);
    final json = _decode(response, 'send message');

    return PushoverMessageResult(
      request: json['request']?.toString() ?? '',
      receipt: json['receipt']?.toString(),
      limits: _limitsFromHeaders(response.headers),
    );
  }

  /// Confirms that [user] — and, when given, [validateDevice] — can receive
  /// messages from this application.
  Future<PushoverValidation> validateUser({String? validateDevice}) async {
    final response = await _post(Uri.parse('$baseUrl/users/validate.json'), {
      'token': token,
      'user': user,
      'device': ?validateDevice,
    });
    final json = _decode(response, 'validate user');

    return PushoverValidation(
      isGroup: _asInt(json['group']) == 1,
      devices: _asStringList(json['devices']),
      licenses: _asStringList(json['licenses']),
    );
  }

  /// Reads the application's remaining monthly message quota.
  Future<PushoverLimits> fetchLimits() async {
    final response = await _get(
      Uri.parse('$baseUrl/apps/limits.json?token=$token'),
    );
    final json = _decode(response, 'fetch limits');
    final reset = _asInt(json['reset']);

    return PushoverLimits(
      limit: _asInt(json['limit']) ?? 0,
      remaining: _asInt(json['remaining']) ?? 0,
      reset: reset == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(reset * 1000, isUtc: true),
    );
  }

  /// Lists the sound names this application may use, mapped to their labels.
  Future<Map<String, String>> fetchSounds() async {
    final response = await _get(Uri.parse('$baseUrl/sounds.json?token=$token'));
    final json = _decode(response, 'fetch sounds');
    final sounds = json['sounds'];

    return switch (sounds) {
      Map<String, Object?>() => {
        for (final entry in sounds.entries)
          entry.key: entry.value?.toString() ?? entry.key,
      },
      _ => const {},
    };
  }

  /// Reads the delivery state of the emergency message identified by
  /// [receipt].
  Future<PushoverReceipt> fetchReceipt(String receipt) async {
    final response = await _get(
      Uri.parse('$baseUrl/receipts/${_receiptPath(receipt)}.json?token=$token'),
    );
    final json = _decode(response, 'fetch receipt');

    return PushoverReceipt(
      acknowledged: _asInt(json['acknowledged']) == 1,
      expired: _asInt(json['expired']) == 1,
      acknowledgedAt: _asTime(json['acknowledged_at']),
      acknowledgedBy: _asNonEmpty(json['acknowledged_by']),
      acknowledgedByDevice: _asNonEmpty(json['acknowledged_by_device']),
      lastDeliveredAt: _asTime(json['last_delivered_at']),
      expiresAt: _asTime(json['expires_at']),
    );
  }

  /// Stops the retries of the emergency message identified by [receipt].
  Future<void> cancelReceipt(String receipt) async {
    final response = await _post(
      Uri.parse('$baseUrl/receipts/${_receiptPath(receipt)}/cancel.json'),
      {'token': token},
    );
    _decode(response, 'cancel receipt');
  }

  /// Validates a receipt id before it becomes part of a URL path.
  ///
  /// Receipt ids reach this client from a model, and a value carrying `?`,
  /// `#`, or `../` would silently redirect the request to a different endpoint
  /// — next to the application token in the query string. Pushover's own ids
  /// are alphanumeric, so anything else is rejected outright.
  static String _receiptPath(String receipt) {
    if (receipt.isEmpty || !RegExp(r'^[A-Za-z0-9]+$').hasMatch(receipt)) {
      throw PushoverApiException(
        'Receipt id "$receipt" is not valid; receipt ids are alphanumeric.',
      );
    }
    return receipt;
  }

  /// Parses a Pushover response, throwing when it reports a failure.
  Map<String, Object?> _decode(PushoverHttpResponse response, String action) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw PushoverApiException(
        'Could not $action: Pushover returned a malformed response '
        '(HTTP ${response.statusCode}). $error',
        statusCode: response.statusCode,
      );
    }

    if (decoded is! Map<String, Object?>) {
      throw PushoverApiException(
        'Could not $action: expected a JSON object but got '
        '${decoded.runtimeType}.',
        statusCode: response.statusCode,
      );
    }

    if (_asInt(decoded['status']) != 1) {
      final errors = _asStringList(decoded['errors']);
      throw PushoverApiException(
        errors.isEmpty
            ? 'Could not $action: Pushover returned HTTP '
                  '${response.statusCode}.'
            : 'Could not $action: ${errors.join('; ')}',
        statusCode: response.statusCode,
        errors: errors,
        request: decoded['request']?.toString(),
      );
    }
    return decoded;
  }

  static PushoverLimits? _limitsFromHeaders(Map<String, String> headers) {
    final limit = int.tryParse(headers['x-limit-app-limit'] ?? '');
    final remaining = int.tryParse(headers['x-limit-app-remaining'] ?? '');
    if (limit == null || remaining == null) return null;
    final reset = int.tryParse(headers['x-limit-app-reset'] ?? '');

    return PushoverLimits(
      limit: limit,
      remaining: remaining,
      reset: reset == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(reset * 1000, isUtc: true),
    );
  }

  static int? _asInt(Object? value) => switch (value) {
    int() => value,
    String() => int.tryParse(value),
    _ => null,
  };

  static DateTime? _asTime(Object? value) {
    final seconds = _asInt(value);
    if (seconds == null || seconds == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  static String? _asNonEmpty(Object? value) {
    final text = value?.toString();
    return text == null || text.isEmpty ? null : text;
  }

  static List<String> _asStringList(Object? value) => switch (value) {
    List() => [for (final item in value) item.toString()],
    _ => const [],
  };
}

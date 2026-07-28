import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'pushover_api.dart';

/// The name of the tool created by [createSendPushoverNotificationTool].
const String sendPushoverNotificationToolName = 'send_pushover_notification';

/// The name of the tool created by [createPushoverLimitsTool].
const String pushoverLimitsToolName = 'get_pushover_limits';

/// The name of the tool created by [createPushoverReceiptTool].
const String pushoverReceiptToolName = 'check_pushover_receipt';

/// Resolves a model-supplied [reference] into an attachment.
///
/// Hosts decide what a reference means — a path in the agent's working folder,
/// a file-store id, a cached screenshot — and are responsible for refusing
/// references that escape whatever boundary they intend. Returning null, or
/// throwing, becomes an error the model reads.
typedef PushoverAttachmentResolver =
    Future<PushoverAttachment?> Function(String reference);

/// Creates a tool that pushes a notification to the [client]'s recipient.
///
/// The recipient and the application token come from [client], not from the
/// model: a model-chosen `user` key would turn this into a sender of arbitrary
/// notifications to arbitrary people. The model chooses only what the message
/// says and how loudly it arrives.
///
/// Emergency priority repeats until a human acknowledges it, so it is opt-in
/// via [allowEmergencyPriority]. When enabled, the model must supply `retry`
/// and `expire`, and the returned receipt id can be polled with
/// [createPushoverReceiptTool].
///
/// Supplying [attachmentResolver] adds an `attachment` argument that takes a
/// reference the host resolves into image bytes. A model cannot emit 5 MiB of
/// image through a JSON string, so the bytes never pass through the schema.
///
/// Encryption is a property of the [client], not an argument: when the client
/// holds an encryptor, [encryptByDefault] sends every message with `message`,
/// `title`, `url`, and `url_title` encrypted end-to-end.
///
/// This tool sends a real notification to a real person every time it is
/// called. Register it deliberately — ideally wrapped in whatever per-call
/// approval the host applies to outbound actions.
AIFunction createSendPushoverNotificationTool({
  required PushoverClient client,
  bool allowEmergencyPriority = false,
  bool allowDeviceTargeting = false,
  bool encryptByDefault = false,
  PushoverAttachmentResolver? attachmentResolver,
}) {
  final priorities = <int>[-2, -1, 0, 1, if (allowEmergencyPriority) 2];

  return AIFunctionFactory.create(
    name: sendPushoverNotificationToolName,
    description:
        'Sends a push notification to the user\'s own devices through '
        'Pushover. Use this to alert the user about something that warrants '
        'interrupting them, or when they ask to be notified. The recipient is '
        'fixed by configuration and cannot be chosen. '
        'The message body is limited to $pushoverMaxMessageLength characters.',
    parametersSchema: {
      'type': 'object',
      'properties': {
        'message': {
          'type': 'string',
          'description':
              'The notification body, at most $pushoverMaxMessageLength '
              'characters.',
        },
        'title': {
          'type': 'string',
          'description':
              'Optional title, at most $pushoverMaxTitleLength characters. '
              'Defaults to the application name.',
        },
        'priority': {
          'type': 'integer',
          'enum': priorities,
          'description':
              '-2 silent (badge only), -1 no sound or vibration, '
              '0 normal (default), 1 high, bypassing the user\'s quiet hours'
              '${allowEmergencyPriority ? ', 2 emergency, repeating until the '
                        'user acknowledges it and requiring retry and expire' : ''}'
              '. Reserve values above 0 for things that genuinely cannot wait.',
        },
        'url': {
          'type': 'string',
          'description':
              'Optional supplementary URL shown with the notification, at '
              'most $pushoverMaxUrlLength characters.',
        },
        'url_title': {
          'type': 'string',
          'description':
              'Optional label for url, at most $pushoverMaxUrlTitleLength '
              'characters. Requires url.',
        },
        'sound': {
          'type': 'string',
          'description':
              'Optional Pushover sound name, such as pushover, magic, or '
              'none. Omit to use the device default.',
        },
        'ttl': {
          'type': 'integer',
          'description':
              'Optional number of seconds after which the notification is '
              'deleted automatically.',
        },
        'monospace': {
          'type': 'boolean',
          'description':
              'Render the message in a monospace font. Use for logs, code, '
              'or tabular output.',
        },
        if (attachmentResolver != null)
          'attachment': {
            'type': 'string',
            'description':
                'Optional reference to an image to attach, such as a file '
                'path in the working folder. One image per notification, at '
                'most $pushoverMaxAttachmentBytes bytes.',
          },
        if (allowDeviceTargeting)
          'device': {
            'type': 'string',
            'description':
                'Optional comma-separated names of the recipient\'s own '
                'devices. Omit to notify every device.',
          },
        if (allowEmergencyPriority) ...{
          'retry': {
            'type': 'integer',
            'description':
                'Emergency priority only: how often, in seconds, to repeat '
                'the notification until it is acknowledged. Minimum '
                '$pushoverMinRetrySeconds.',
          },
          'expire': {
            'type': 'integer',
            'description':
                'Emergency priority only: how long, in seconds, to keep '
                'retrying. Maximum $pushoverMaxExpireSeconds.',
          },
        },
      },
      'required': ['message'],
      'additionalProperties': false,
    },
    returnSchema: const {
      'type': 'object',
      'properties': {
        'request': {'type': 'string'},
        'receipt': {'type': 'string'},
        'messagesRemaining': {'type': 'integer'},
      },
      'required': ['request'],
      'additionalProperties': false,
    },
    callback: (arguments, {CancellationToken? cancellationToken}) async {
      final message = _string(arguments['message']);
      if (message == null) {
        return 'Error sending notification: message is required.';
      }

      final priorityValue = _int(arguments['priority']) ?? 0;
      final priority = PushoverPriority.fromValue(priorityValue);
      if (priority == null || !priorities.contains(priorityValue)) {
        return 'Error sending notification: priority must be one of '
            '${priorities.join(', ')}.';
      }

      final reference = _string(arguments['attachment']);
      PushoverAttachment? attachment;
      if (reference != null && attachmentResolver != null) {
        try {
          attachment = await attachmentResolver(reference);
        } catch (error) {
          return 'Error sending notification: could not read the attachment '
              '"$reference". $error';
        }
        if (attachment == null) {
          return 'Error sending notification: no attachment found for '
              '"$reference".';
        }
      }

      try {
        final result = await client.send(
          PushoverMessage(
            message: message,
            attachment: attachment,
            encrypt: encryptByDefault,
            title: _string(arguments['title']),
            priority: priority,
            sound: _string(arguments['sound']),
            url: _string(arguments['url']),
            urlTitle: _string(arguments['url_title']),
            device: allowDeviceTargeting ? _string(arguments['device']) : null,
            ttl: _int(arguments['ttl']),
            monospace: arguments['monospace'] == true,
            retry: allowEmergencyPriority ? _int(arguments['retry']) : null,
            expire: allowEmergencyPriority ? _int(arguments['expire']) : null,
          ),
        );
        return result.toJson();
      } on PushoverApiException catch (error) {
        // Pushover's own wording ("message cannot be blank", "sound is
        // invalid") tells the model how to fix the call, so pass it through
        // rather than throwing.
        return 'Error sending notification: ${error.message}';
      } catch (error) {
        return 'Error sending notification: $error';
      }
    },
  );
}

/// Creates a tool that reports how much of the application's monthly Pushover
/// quota is left.
///
/// Useful when an agent decides whether a notification is worth spending, and
/// as a cheap way to confirm the application token works.
AIFunction createPushoverLimitsTool({required PushoverClient client}) =>
    AIFunctionFactory.create(
      name: pushoverLimitsToolName,
      description:
          'Returns the Pushover application\'s monthly message quota: the '
          'limit, how many messages remain, and when the quota resets.',
      parametersSchema: const {
        'type': 'object',
        'properties': <String, Object?>{},
        'additionalProperties': false,
      },
      returnSchema: const {
        'type': 'object',
        'properties': {
          'limit': {'type': 'integer'},
          'remaining': {'type': 'integer'},
          'resetsAt': {'type': 'string'},
        },
        'required': ['limit', 'remaining'],
        'additionalProperties': false,
      },
      callback: (arguments, {CancellationToken? cancellationToken}) async {
        try {
          return (await client.fetchLimits()).toJson();
        } on PushoverApiException catch (error) {
          return 'Error reading Pushover limits: ${error.message}';
        } catch (error) {
          return 'Error reading Pushover limits: $error';
        }
      },
    );

/// Creates a tool that reads whether an emergency notification has been
/// acknowledged, and can cancel its retries.
///
/// Only useful alongside a send tool created with `allowEmergencyPriority`,
/// since receipts exist only for emergency-priority messages.
AIFunction createPushoverReceiptTool({required PushoverClient client}) =>
    AIFunctionFactory.create(
      name: pushoverReceiptToolName,
      description:
          'Checks whether an emergency-priority Pushover notification has '
          'been acknowledged, using the receipt id returned when it was sent. '
          'Set cancel to true to stop the notification from repeating.',
      parametersSchema: const {
        'type': 'object',
        'properties': {
          'receipt': {
            'type': 'string',
            'description':
                'The receipt id returned by '
                '$sendPushoverNotificationToolName.',
          },
          'cancel': {
            'type': 'boolean',
            'description':
                'Stop the notification from repeating. Defaults to false.',
          },
        },
        'required': ['receipt'],
        'additionalProperties': false,
      },
      callback: (arguments, {CancellationToken? cancellationToken}) async {
        final receipt = _string(arguments['receipt']);
        if (receipt == null) {
          return 'Error checking receipt: receipt is required.';
        }

        try {
          if (arguments['cancel'] == true) {
            await client.cancelReceipt(receipt);
            return 'Cancelled the retries for receipt $receipt.';
          }
          return (await client.fetchReceipt(receipt)).toJson();
        } on PushoverApiException catch (error) {
          return 'Error checking receipt: ${error.message}';
        } catch (error) {
          return 'Error checking receipt: $error';
        }
      },
    );

/// Reads [value] as a non-empty trimmed string, or null.
String? _string(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

/// Reads [value] as an integer, tolerating the string and double forms models
/// produce when a schema asks for one.
int? _int(Object? value) => switch (value) {
  int() => value,
  double() => value.toInt(),
  String() => int.tryParse(value.trim()),
  _ => null,
};

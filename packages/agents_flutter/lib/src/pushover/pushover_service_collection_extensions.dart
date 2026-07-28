import 'package:agents/agents.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';

import 'pushover_api.dart';
import 'pushover_encryption.dart';
import 'pushover_tool.dart';

/// Registers the Pushover client and its tools.
extension PushoverServiceCollectionExtensions on ServiceCollection {
  /// Registers a [PushoverClient] and the tools that use it.
  ///
  /// Registration is deliberately explicit rather than part of a default
  /// capability set: unlike the passive device tools, these send a real
  /// notification to a real person. [token] is the Pushover application token
  /// and [user] the recipient's user or group key; neither is exposed to the
  /// model.
  ///
  /// A [PushoverClient] registered before this method is preserved, which is
  /// how a caller supplies credentials from secure storage or swaps in a fake.
  /// Omitting [token] and [user] without having registered one throws here,
  /// rather than at agent-build time where the missing client would take down
  /// the resolution of every other [AITool] with it.
  ///
  /// [allowEmergencyPriority] permits messages that repeat until acknowledged
  /// and registers the receipt tool alongside them.
  ///
  /// [encryptionHexKey] is the recipient's 64-character end-to-end encryption
  /// key; supplying it makes every notification encrypted. It only applies to
  /// a client constructed here, since a pre-registered client carries its own
  /// encryptor.
  ServiceCollection addPushover({
    String? token,
    String? user,
    String? device,
    String? encryptionHexKey,
    bool includeLimitsTool = true,
    bool allowEmergencyPriority = false,
    bool allowDeviceTargeting = false,
    PushoverAttachmentResolver? attachmentResolver,
  }) {
    if (token != null && user != null) {
      final encryptor = encryptionHexKey == null
          ? null
          : PushoverAesEncryptor.fromHexKey(encryptionHexKey);
      tryAddSingleton<PushoverClient>(
        (_) => PushoverClient(
          token: token,
          user: user,
          device: device,
          encryptor: encryptor?.call,
        ),
      );
    } else if (!any((descriptor) => descriptor.serviceType == PushoverClient)) {
      throw ArgumentError(
        'addPushover needs both a token and a user key, or a PushoverClient '
        'registered before it is called.',
      );
    }

    addSingleton<AITool>(
      (services) => createSendPushoverNotificationTool(
        client: services.getRequiredService<PushoverClient>(),
        allowEmergencyPriority: allowEmergencyPriority,
        allowDeviceTargeting: allowDeviceTargeting,
        encryptByDefault: encryptionHexKey != null,
        attachmentResolver: attachmentResolver,
      ),
    );

    if (includeLimitsTool) {
      addSingleton<AITool>(
        (services) => createPushoverLimitsTool(
          client: services.getRequiredService<PushoverClient>(),
        ),
      );
    }

    if (allowEmergencyPriority) {
      addSingleton<AITool>(
        (services) => createPushoverReceiptTool(
          client: services.getRequiredService<PushoverClient>(),
        ),
      );
    }

    return this;
  }
}

/// Adds Pushover tools to [ChatClientAgentOptions].
extension PushoverChatClientAgentOptionsExtensions on ChatClientAgentOptions {
  /// Appends the Pushover tools, retaining any tools already configured.
  ///
  /// The caller supplies [client] so the credentials it holds have a single
  /// owner. Use `ServiceCollection.addPushover` when the service provider
  /// should own the client instead.
  ChatClientAgentOptions addPushoverTools({
    required PushoverClient client,
    bool includeLimitsTool = true,
    bool allowEmergencyPriority = false,
    bool allowDeviceTargeting = false,
    bool encryptByDefault = false,
    PushoverAttachmentResolver? attachmentResolver,
  }) {
    chatOptions ??= ChatOptions();
    chatOptions!.tools = [
      ...?chatOptions!.tools,
      createSendPushoverNotificationTool(
        client: client,
        allowEmergencyPriority: allowEmergencyPriority,
        allowDeviceTargeting: allowDeviceTargeting,
        encryptByDefault: encryptByDefault,
        attachmentResolver: attachmentResolver,
      ),
      if (includeLimitsTool) createPushoverLimitsTool(client: client),
      if (allowEmergencyPriority) createPushoverReceiptTool(client: client),
    ];

    return this;
  }
}

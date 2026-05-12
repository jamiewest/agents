import 'package:extensions/ai.dart';

import '../../abstractions/ai_context_provider.dart';
import 'ai_context_provider_chat_client.dart';

/// Provides extension methods for adding [AIContextProvider] support to
/// [ChatClientBuilder] instances.
extension AIContextProviderChatClientBuilderExtensions on ChatClientBuilder {
  ChatClientBuilder useAIContextProviders(List<AIContextProvider> providers) {
    return use(
      (innerClient) => AIContextProviderChatClient(innerClient, providers),
    );
  }
}

import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/hosting/agent_hosting_service_collection_extensions.dart';
import 'package:agents/src/hosting/hosted_agent_builder.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

ServiceCollection _servicesWithClient() {
  final services = ServiceCollection();
  services.addSingleton<ChatClient>((_) => _FakeChatClient());
  return services;
}

void main() {
  group('AgentHostingServiceCollectionExtensions', () {
    test('addAIAgent_RegistersKeyedSingleton', () {
      final services = _servicesWithClient();
      services.addAIAgent('myAgent', ServiceLifetime.singleton);
      final provider = services.buildServiceProvider();

      final agent = provider.getKeyedService<AIAgent>('myAgent');
      expect(agent, isA<AIAgent>());
    });

    test('addAIAgent_WithNoTools_DoesNotThrow', () {
      final services = _servicesWithClient();
      services.addAIAgent('myAgent', ServiceLifetime.singleton);
      final provider = services.buildServiceProvider();

      expect(
        () => provider.getKeyedService<AIAgent>('myAgent'),
        returnsNormally,
      );
    });

    test('addAIAgent_MultipleCalls_RegistersMultipleAgents', () {
      final services = _servicesWithClient();
      services.addAIAgent('firstAgent', ServiceLifetime.singleton);
      services.addAIAgent('secondAgent', ServiceLifetime.singleton);
      final provider = services.buildServiceProvider();

      expect(provider.getKeyedService<AIAgent>('firstAgent'), isA<AIAgent>());
      expect(provider.getKeyedService<AIAgent>('secondAgent'), isA<AIAgent>());
      expect(
        provider.getKeyedService<AIAgent>('firstAgent'),
        isNot(same(provider.getKeyedService<AIAgent>('secondAgent'))),
      );
    });

    test('addAIAgent_ReturnsHostedAgentBuilder', () {
      final services = _servicesWithClient();

      final builder = services.addAIAgent(
        'myAgent',
        ServiceLifetime.singleton,
      );

      expect(builder, isA<HostedAgentBuilder>());
      expect(builder.name, 'myAgent');
      expect(builder.lifetime, ServiceLifetime.singleton);
    });
  });
}

class _FakeChatClient implements ChatClient {
  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async =>
      ChatResponse.fromMessage(
        ChatMessage.fromText(ChatRole.assistant, 'unused'),
      );

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {}

  @override
  T? getService<T>({Object? key}) => null;

  @override
  void dispose() {}
}


// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents/agents.dart'
    show
        AgentModeProvider,
        AIAgent,
        BackgroundAgentsProvider,
        ChatClientAgent,
        FileAccessProvider,
        FileMemoryProvider,
        LoopAgent,
        TodoProvider,
        ToolApprovalAgent;
import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _openAiSource = ModelSourceConfig(
  id: 's-openai',
  providerType: ProviderType.openAiCompatible,
  displayName: 'Local',
  endpoint: 'http://localhost:4321/v1',
);
const _openAiModel = ModelConfig(
  id: 'm-openai',
  sourceId: 's-openai',
  modelId: 'gpt-test',
);
const _anthropicSource = ModelSourceConfig(
  id: 's-anthropic',
  providerType: ProviderType.anthropic,
  displayName: 'Anthropic',
);
const _anthropicModel = ModelConfig(
  id: 'm-anthropic',
  sourceId: 's-anthropic',
  modelId: 'claude-test',
);
const _googleSource = ModelSourceConfig(
  id: 's-google',
  providerType: ProviderType.google,
  displayName: 'Google',
);
const _googleModel = ModelConfig(
  id: 'm-google',
  sourceId: 's-google',
  modelId: 'gemini-test',
);
const _localSource = ModelSourceConfig(
  id: 's-local',
  providerType: ProviderType.localLlama,
  displayName: 'Local llama',
);
const _localModel = ModelConfig(
  id: 'm-local',
  sourceId: 's-local',
  modelId: 'local-gemma',
  settings: {'llama.modelUrl': 'https://example.com/model.gguf'},
);

/// Captures the first outgoing request, then returns a canned 200 so the
/// client has something to (attempt to) parse.
class _Capture {
  http.BaseRequest? request;

  MockClient client(String body) => MockClient((req) async {
    request ??= req;
    return http.Response(body, 200);
  });
}

Future<void> _ignoreParseErrors(Future<void> Function() action) async {
  try {
    await action();
  } catch (_) {
    // The canned body is not a valid provider response; we only care that the
    // request reached the wire so its headers/URL can be inspected.
  }
}

ChatClient _staticEchoResolver({
  required ModelSourceConfig source,
  required ModelConfig model,
  http.Client? httpClient,
}) => _EchoChatClient();

final class _EchoChatClient extends ChatClient {
  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async => ChatResponse(
    messages: <ChatMessage>[ChatMessage.fromText(ChatRole.assistant, 'ok')],
  );

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) => Stream<ChatResponseUpdate>.value(
    ChatResponseUpdate.fromText(ChatRole.assistant, 'ok'),
  );

  @override
  T? getService<T>({Object? key}) => null;

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConfiguredChatClientFactory', () {
    test(
      'targets the configured OpenAI-compatible endpoint with the key',
      () async {
        final capture = _Capture();
        final client = const ConfiguredChatClientFactory().createChatClient(
          source: _openAiSource,
          model: _openAiModel,
          apiKey: 'sk-openai',
          httpClient: capture.client('{}'),
        );

        await _ignoreParseErrors(
          () => client.getResponse(
            messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
          ),
        );

        final request = capture.request!;
        expect(request.url.host, 'localhost');
        expect(request.url.port, 4321);
        expect(request.headers['Authorization'], contains('sk-openai'));
      },
    );

    test('builds a Gemini client targeting the Google endpoint', () async {
      final capture = _Capture();
      final client = const ConfiguredChatClientFactory().createChatClient(
        source: _googleSource,
        model: _googleModel,
        apiKey: 'goog-key',
        httpClient: capture.client('{}'),
      );

      await _ignoreParseErrors(
        () => client.getResponse(
          messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
        ),
      );

      final request = capture.request!;
      expect(request.url.host, 'generativelanguage.googleapis.com');
      expect(request.url.path, contains('gemini-test'));
      expect(request.headers['x-goog-api-key'], 'goog-key');
    });

    test('uses a custom endpoint override for Google when provided', () async {
      final capture = _Capture();
      final client = const ConfiguredChatClientFactory().createChatClient(
        source: const ModelSourceConfig(
          id: 's-google-proxy',
          providerType: ProviderType.google,
          displayName: 'Google proxy',
          endpoint: 'https://proxy.example.com/v1beta',
        ),
        model: _googleModel,
        apiKey: 'goog-key',
        httpClient: capture.client('{}'),
      );

      await _ignoreParseErrors(
        () => client.getResponse(
          messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
        ),
      );

      expect(capture.request!.url.host, 'proxy.example.com');
    });

    test('attaches the Anthropic browser header when isWeb is true', () async {
      final capture = _Capture();
      final client = const ConfiguredChatClientFactory(isWeb: true)
          .createChatClient(
            source: _anthropicSource,
            model: _anthropicModel,
            apiKey: 'sk-ant',
            httpClient: capture.client('{}'),
          );

      await _ignoreParseErrors(
        () => client.getResponse(
          messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
        ),
      );

      expect(
        capture.request!.headers,
        containsPair('anthropic-dangerous-direct-browser-access', 'true'),
      );
    });

    test('omits the Anthropic browser header when isWeb is false', () async {
      final capture = _Capture();
      final client = const ConfiguredChatClientFactory(isWeb: false)
          .createChatClient(
            source: _anthropicSource,
            model: _anthropicModel,
            apiKey: 'sk-ant',
            httpClient: capture.client('{}'),
          );

      await _ignoreParseErrors(
        () => client.getResponse(
          messages: [ChatMessage.fromText(ChatRole.user, 'hi')],
        ),
      );

      expect(
        capture.request!.headers.keys,
        isNot(contains('anthropic-dangerous-direct-browser-access')),
      );
    });

    test('rejects an API key with a non-Latin-1 character', () {
      // A right single quotation mark (U+2019) is a common paste artifact that
      // browser fetch cannot send as a header value.
      const factory = ConfiguredChatClientFactory();

      expect(
        () => factory.createChatClient(
          source: _anthropicSource,
          model: _anthropicModel,
          apiKey: 'sk-ant’key',
        ),
        throwsA(
          isA<ConfiguredAgentException>().having(
            (e) => e.message,
            'message',
            contains('U+2019'),
          ),
        ),
      );
    });

    test('accepts a plain ASCII API key', () {
      const factory = ConfiguredChatClientFactory();

      expect(
        () => factory.createChatClient(
          source: _anthropicSource,
          model: _anthropicModel,
          apiKey: 'sk-ant-api03-abcDEF123',
        ),
        returnsNormally,
      );
    });

    test('uses the custom resolver for local llama without an API key', () {
      final client = const ConfiguredChatClientFactory(
        customClientResolver: _staticEchoResolver,
      ).createChatClient(source: _localSource, model: _localModel);

      // Every provider client is wrapped so attached text files reach the
      // model as prompt text.
      expect(
        client,
        isA<TextFileInliningChatClient>().having(
          (c) => c.innerClient,
          'innerClient',
          isA<_EchoChatClient>(),
        ),
      );
    });

    test('throws when local llama has no custom resolver', () {
      expect(
        () => const ConfiguredChatClientFactory().createChatClient(
          source: _localSource,
          model: _localModel,
        ),
        throwsA(
          isA<ConfiguredAgentException>().having(
            (e) => e.message,
            'message',
            'No local-model provider registered.',
          ),
        ),
      );
    });
  });

  group('ConfiguredAgentFactory', () {
    ConfiguredAgentsManager buildManager() {
      final kv = InMemoryKeyValueStore();
      return ConfiguredAgentsManager(
        sources: ModelSourceStore(kv),
        agents: AgentConfigurationStore(kv),
        secrets: InMemorySecretStore(),
      );
    }

    test('throws when the model is missing', () async {
      final manager = buildManager();
      await manager.saveAgent(
        const SavedAgentConfig(id: 'a1', name: 'Helper', modelId: 'missing'),
      );

      await expectLater(
        ConfiguredAgentFactory(manager).createAgentById('a1'),
        throwsA(isA<ConfiguredAgentException>()),
      );
    });

    test('throws when no API key is stored', () async {
      final manager = buildManager();
      await manager.saveSource(_anthropicSource);
      await manager.saveModel(_anthropicModel);
      await manager.saveAgent(
        const SavedAgentConfig(
          id: 'a1',
          name: 'Helper',
          modelId: 'm-anthropic',
        ),
      );

      await expectLater(
        ConfiguredAgentFactory(manager).createAgent(
          const SavedAgentConfig(
            id: 'a1',
            name: 'Helper',
            modelId: 'm-anthropic',
          ),
        ),
        throwsA(isA<ConfiguredAgentException>()),
      );
    });

    test('creates a local llama agent without a stored API key', () async {
      final manager = buildManager();
      await manager.saveSource(_localSource);
      await manager.saveModel(_localModel);
      const agent = SavedAgentConfig(
        id: 'a-local',
        name: 'Local',
        modelId: 'm-local',
      );
      await manager.saveAgent(agent);

      final built = await ConfiguredAgentFactory(
        manager,
        chatClientFactory: const ConfiguredChatClientFactory(
          customClientResolver: _staticEchoResolver,
        ),
      ).createAgent(agent);
      final chatOptions = built.getServiceOf<ChatOptions>()!;

      expect(built.name, 'Local');
      expect(chatOptions.modelId, 'local-gemma');
    });

    test('builds a Flutter harness agent when fully configured', () async {
      final manager = buildManager();
      await manager.saveSource(_openAiSource, apiKey: 'sk-openai');
      await manager.saveModel(_openAiModel);
      const agent = SavedAgentConfig(
        id: 'a1',
        name: 'Helper',
        modelId: 'm-openai',
        instructions: 'be brief',
        temperature: 0.2,
        maxOutputTokens: 321,
      );
      await manager.saveAgent(agent);

      final built = await ConfiguredAgentFactory(manager).createAgent(agent);
      final inner = built.getServiceOf<ChatClientAgent>()!;
      final providerTypes = inner.aiContextProviders!
          .map((provider) => provider.runtimeType)
          .toList();
      final chatOptions = built.getServiceOf<ChatOptions>()!;
      final toolNames = chatOptions.tools!.map((tool) => tool.name).toList();

      expect(built.name, 'Helper');
      expect(providerTypes, contains(TodoProvider));
      expect(providerTypes, contains(AgentModeProvider));
      expect(providerTypes, contains(ConnectivityContextProvider));
      expect(toolNames, contains('get_connectivity'));
      expect(chatOptions.modelId, 'gpt-test');
      expect(chatOptions.instructions, contains('be brief'));
      expect(chatOptions.temperature, 0.2);
      expect(chatOptions.maxOutputTokens, 321);
    });

    test(
      'uses a safe default max output when the saved agent is blank',
      () async {
        final manager = buildManager();
        await manager.saveSource(_anthropicSource, apiKey: 'sk-ant');
        await manager.saveModel(_anthropicModel);
        const agent = SavedAgentConfig(
          id: 'a1',
          name: 'Helper',
          modelId: 'm-anthropic',
        );
        await manager.saveAgent(agent);

        final built = await ConfiguredAgentFactory(manager).createAgent(agent);
        final chatOptions = built.getServiceOf<ChatOptions>()!;

        expect(chatOptions.modelId, 'claude-test');
        expect(
          chatOptions.maxOutputTokens,
          defaultConfiguredAgentMaxOutputTokens,
        );
      },
    );

    test(
      'applies configured harness options before saved agent settings',
      () async {
        final manager = buildManager();
        await manager.saveSource(_openAiSource, apiKey: 'sk-openai');
        await manager.saveModel(_openAiModel);
        const agent = SavedAgentConfig(
          id: 'a1',
          name: 'Helper',
          modelId: 'm-openai',
          instructions: 'saved instructions',
          maxOutputTokens: 256,
        );
        await manager.saveAgent(agent);

        final built = await ConfiguredAgentFactory(
          manager,
          configureHarness: (options) => options
            ..enableWakeLock = true
            ..disableTodoProvider = true
            ..chatOptions = ChatOptions(
              instructions: 'shared instructions',
              temperature: 0.8,
              maxOutputTokens: 999,
            ),
        ).createAgent(agent);
        final inner = built.getServiceOf<ChatClientAgent>()!;
        final providerTypes = inner.aiContextProviders!
            .map((provider) => provider.runtimeType)
            .toList();
        final chatOptions = built.getServiceOf<ChatOptions>()!;
        final toolNames = chatOptions.tools!.map((tool) => tool.name).toList();

        expect(providerTypes, isNot(contains(TodoProvider)));
        expect(providerTypes, contains(ConnectivityContextProvider));
        expect(toolNames, contains('set_wake_lock'));
        expect(chatOptions.instructions, contains('saved instructions'));
        expect(
          chatOptions.instructions,
          isNot(contains('shared instructions')),
        );
        // A saved agent without a temperature falls back to the harness
        // value instead of clobbering it with null, matching the
        // maxOutputTokens fallback below.
        expect(chatOptions.temperature, 0.8);
        expect(chatOptions.maxOutputTokens, 256);
      },
    );

    test('a saved agent temperature overrides the harness value', () async {
      final manager = buildManager();
      await manager.saveSource(_openAiSource, apiKey: 'sk-openai');
      await manager.saveModel(_openAiModel);
      const agent = SavedAgentConfig(
        id: 'a1',
        name: 'Helper',
        modelId: 'm-openai',
        temperature: 0.1,
      );
      await manager.saveAgent(agent);

      final built = await ConfiguredAgentFactory(
        manager,
        configureHarness: (options) =>
            options.chatOptions = ChatOptions(temperature: 0.8),
      ).createAgent(agent);
      final chatOptions = built.getServiceOf<ChatOptions>()!;

      expect(chatOptions.temperature, 0.1);
    });

    test(
      'uses shared harness max output when the saved agent is blank',
      () async {
        final manager = buildManager();
        await manager.saveSource(_openAiSource, apiKey: 'sk-openai');
        await manager.saveModel(_openAiModel);
        const agent = SavedAgentConfig(
          id: 'a1',
          name: 'Helper',
          modelId: 'm-openai',
        );
        await manager.saveAgent(agent);

        final built = await ConfiguredAgentFactory(
          manager,
          configureHarness: (options) =>
              options.chatOptions = ChatOptions(maxOutputTokens: 512),
        ).createAgent(agent);
        final chatOptions = built.getServiceOf<ChatOptions>()!;

        expect(chatOptions.maxOutputTokens, 512);
      },
    );

    test(
      'applies saved agent access settings to harness capabilities',
      () async {
        final manager = buildManager();
        await manager.saveSource(_openAiSource, apiKey: 'sk-openai');
        await manager.saveModel(_openAiModel);
        const agent = SavedAgentConfig(
          id: 'a1',
          name: 'Helper',
          modelId: 'm-openai',
          access: AgentAccessConfig(
            enableFileMemory: false,
            enableFileAccess: false,
            enableWebSearch: false,
            enableTodoList: false,
            enableAgentMode: false,
            enableSkills: false,
            enableTemporal: false,
            enableConnectivity: false,
            enableAppInfo: false,
            enableDeviceInfo: false,
            enableLocation: true,
            enableNetworkInfo: true,
            enableWakeLock: true,
            enableShell: true,
          ),
        );
        await manager.saveAgent(agent);

        final built = await ConfiguredAgentFactory(manager).createAgent(agent);
        final inner = built.getServiceOf<ChatClientAgent>()!;
        final providerTypes = inner.aiContextProviders!
            .map((provider) => provider.runtimeType)
            .toList();
        final providerTypeNames = providerTypes
            .map((type) => type.toString())
            .toList();
        final chatOptions = built.getServiceOf<ChatOptions>()!;
        final tools = chatOptions.tools!;
        final toolNames = tools.map((tool) => tool.name).toList();

        expect(providerTypes, isNot(contains(TodoProvider)));
        expect(providerTypes, isNot(contains(AgentModeProvider)));
        expect(providerTypes, isNot(contains(FileMemoryProvider)));
        expect(providerTypes, isNot(contains(FileAccessProvider)));
        expect(providerTypeNames, isNot(contains('AgentSkillsProvider')));
        expect(providerTypes, isNot(contains(ConnectivityContextProvider)));
        expect(providerTypes, contains(LocationContextProvider));
        // Network info is tool-only: the provider would poll six platform
        // channels per turn and inject volatile text into instructions.
        expect(providerTypes, isNot(contains(NetworkContextProvider)));

        expect(
          tools.map((tool) => tool.runtimeType.toString()),
          isNot(contains('HostedWebSearchTool')),
        );
        expect(toolNames, isNot(contains('get_current_time')));
        expect(toolNames, isNot(contains('get_connectivity')));
        expect(toolNames, isNot(contains('get_app_info')));
        expect(toolNames, isNot(contains('get_device_info')));
        expect(toolNames, contains('get_current_location'));
        expect(toolNames, contains('geocode_address'));
        expect(toolNames, contains('get_current_network_info'));
        expect(toolNames, contains('set_wake_lock'));
        expect(toolNames, contains('run_shell'));
      },
    );

    test(
      'wraps the agent for file tool auto-approval, keeping the harness',
      () async {
        final manager = buildManager();
        await manager.saveSource(_openAiSource, apiKey: 'sk-openai');
        await manager.saveModel(_openAiModel);
        const agent = SavedAgentConfig(
          id: 'a1',
          name: 'Helper',
          modelId: 'm-openai',
          access: AgentAccessConfig(
            fileToolApprovalMode: FileToolApprovalMode.autoApproveReadOnly,
          ),
        );
        await manager.saveAgent(agent);

        final built = await ConfiguredAgentFactory(manager).createAgent(agent);

        expect(built, isA<ToolApprovalAgent>());
        expect(built.getServiceOf<ChatClientAgent>(), isNotNull);
        expect(built.name, 'Helper');
      },
    );

    test('always-ask approval mode keeps the plain harness agent', () async {
      final manager = buildManager();
      await manager.saveSource(_openAiSource, apiKey: 'sk-openai');
      await manager.saveModel(_openAiModel);
      const agent = SavedAgentConfig(
        id: 'a1',
        name: 'Helper',
        modelId: 'm-openai',
        access: AgentAccessConfig(),
      );
      await manager.saveAgent(agent);

      final built = await ConfiguredAgentFactory(manager).createAgent(agent);

      expect(built, isNot(isA<ToolApprovalAgent>()));
      expect(built, isA<FlutterHarnessAgent>());
    });

    test(
      'read-only file access still exposes one file access provider',
      () async {
        final manager = buildManager();
        await manager.saveSource(_openAiSource, apiKey: 'sk-openai');
        await manager.saveModel(_openAiModel);
        const agent = SavedAgentConfig(
          id: 'a1',
          name: 'Helper',
          modelId: 'm-openai',
          access: AgentAccessConfig(enableFileWriteTools: false),
        );
        await manager.saveAgent(agent);

        final built = await ConfiguredAgentFactory(manager).createAgent(agent);
        final inner = built.getServiceOf<ChatClientAgent>()!;
        final fileAccessProviders = inner.aiContextProviders!
            .whereType<FileAccessProvider>()
            .toList();

        expect(fileAccessProviders, hasLength(1));
      },
    );

    group('delegation', () {
      Future<ConfiguredAgentsManager> buildOpenAiManager() async {
        final manager = buildManager();
        await manager.saveSource(_openAiSource, apiKey: 'sk-openai');
        await manager.saveModel(_openAiModel);
        return manager;
      }

      List<Type> providerTypesOf(AIAgent built) => built
          .getServiceOf<ChatClientAgent>()!
          .aiContextProviders!
          .map((provider) => provider.runtimeType)
          .toList();

      test('attaches background agents only when delegations exist', () async {
        final manager = await buildOpenAiManager();
        const accounting = SavedAgentConfig(
          id: 'a2',
          name: 'Accounting',
          modelId: 'm-openai',
        );
        const primary = SavedAgentConfig(
          id: 'a1',
          name: 'Helper',
          modelId: 'm-openai',
          delegations: [
            AgentDelegationConfig(
              agentId: 'a2',
              instructions: 'Use for cost schedules.',
            ),
          ],
        );
        await manager.saveAgent(accounting);
        await manager.saveAgent(primary);
        final factory = ConfiguredAgentFactory(manager);

        final withDelegates = await factory.createAgent(primary);
        final withoutDelegates = await factory.createAgent(accounting);

        expect(
          providerTypesOf(withDelegates),
          contains(BackgroundAgentsProvider),
        );
        expect(
          providerTypesOf(withoutDelegates),
          isNot(contains(BackgroundAgentsProvider)),
        );
      });

      test(
        'loops a delegating agent until background tasks complete',
        () async {
          final manager = await buildOpenAiManager();
          const accounting = SavedAgentConfig(
            id: 'a2',
            name: 'Accounting',
            modelId: 'm-openai',
          );
          const primary = SavedAgentConfig(
            id: 'a1',
            name: 'Helper',
            modelId: 'm-openai',
            delegations: [AgentDelegationConfig(agentId: 'a2')],
          );
          await manager.saveAgent(accounting);
          await manager.saveAgent(primary);
          final factory = ConfiguredAgentFactory(manager);

          final withDelegates = await factory.createAgent(primary);
          final withoutDelegates = await factory.createAgent(accounting);

          expect(withDelegates, isA<LoopAgent>());
          expect(withoutDelegates, isNot(isA<LoopAgent>()));
        },
      );

      test(
        'delegate list text includes names, descriptions, and guidance',
        () async {
          final manager = await buildOpenAiManager();
          const accounting = SavedAgentConfig(
            id: 'a2',
            name: 'Accounting',
            modelId: 'm-openai',
            description: 'Cost and finance work.',
          );
          await manager.saveAgent(accounting);
          final delegate = await ConfiguredAgentFactory(
            manager,
          ).createAgent(accounting);

          final text = ConfiguredAgentFactory.buildDelegateAgentListText(
            {'Accounting': delegate},
            {'accounting': 'Use for cost schedules.'},
          );

          expect(text, contains('- Accounting: Cost and finance work.'));
          expect(text, contains('Guidance: Use for cost schedules.'));
        },
      );

      test('throws when a delegate no longer exists', () async {
        final manager = await buildOpenAiManager();
        const primary = SavedAgentConfig(
          id: 'a1',
          name: 'Helper',
          modelId: 'm-openai',
          delegations: [AgentDelegationConfig(agentId: 'missing')],
        );

        await expectLater(
          ConfiguredAgentFactory(manager).createAgent(primary),
          throwsA(isA<ConfiguredAgentException>()),
        );
      });

      test('throws on self-delegation', () async {
        final manager = await buildOpenAiManager();
        const primary = SavedAgentConfig(
          id: 'a1',
          name: 'Helper',
          modelId: 'm-openai',
          delegations: [AgentDelegationConfig(agentId: 'a1')],
        );

        await expectLater(
          ConfiguredAgentFactory(manager).createAgent(primary),
          throwsA(isA<ConfiguredAgentException>()),
        );
      });

      test('throws when delegate names collide case-insensitively', () async {
        final manager = await buildOpenAiManager();
        await manager.saveAgent(
          const SavedAgentConfig(
            id: 'a2',
            name: 'Accounting',
            modelId: 'm-openai',
          ),
        );
        await manager.saveAgent(
          const SavedAgentConfig(
            id: 'a3',
            name: 'accounting',
            modelId: 'm-openai',
          ),
        );
        const primary = SavedAgentConfig(
          id: 'a1',
          name: 'Helper',
          modelId: 'm-openai',
          delegations: [
            AgentDelegationConfig(agentId: 'a2'),
            AgentDelegationConfig(agentId: 'a3'),
          ],
        );

        await expectLater(
          ConfiguredAgentFactory(manager).createAgent(primary),
          throwsA(isA<ConfiguredAgentException>()),
        );
      });

      test('builds delegates with their own model configuration', () async {
        // The delegate's Anthropic source has no stored API key, so building
        // the primary must fail while resolving the delegate.
        final manager = await buildOpenAiManager();
        await manager.saveSource(_anthropicSource);
        await manager.saveModel(_anthropicModel);
        await manager.saveAgent(
          const SavedAgentConfig(
            id: 'a2',
            name: 'Accounting',
            modelId: 'm-anthropic',
          ),
        );
        const primary = SavedAgentConfig(
          id: 'a1',
          name: 'Helper',
          modelId: 'm-openai',
          delegations: [AgentDelegationConfig(agentId: 'a2')],
        );

        await expectLater(
          ConfiguredAgentFactory(manager).createAgent(primary),
          throwsA(isA<ConfiguredAgentException>()),
        );
      });

      test('cyclic delegation builds without nested delegates', () async {
        final manager = await buildOpenAiManager();
        await manager.saveAgent(
          const SavedAgentConfig(id: 'a1', name: 'Helper', modelId: 'm-openai'),
        );
        await manager.saveAgent(
          const SavedAgentConfig(
            id: 'a2',
            name: 'Accounting',
            modelId: 'm-openai',
            delegations: [AgentDelegationConfig(agentId: 'a1')],
          ),
        );
        await manager.saveAgent(
          const SavedAgentConfig(
            id: 'a1',
            name: 'Helper',
            modelId: 'm-openai',
            delegations: [AgentDelegationConfig(agentId: 'a2')],
          ),
        );

        // Without the nested-delegation guard this would recurse forever.
        final built = await ConfiguredAgentFactory(
          manager,
        ).createAgentById('a1');

        expect(providerTypesOf(built), contains(BackgroundAgentsProvider));
      });
    });
  });
}

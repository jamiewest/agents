// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
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

void main() {
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

    test('builds an agent when fully configured', () async {
      final manager = buildManager();
      await manager.saveSource(_openAiSource, apiKey: 'sk-openai');
      await manager.saveModel(_openAiModel);
      const agent = SavedAgentConfig(
        id: 'a1',
        name: 'Helper',
        modelId: 'm-openai',
        instructions: 'be brief',
        temperature: 0.2,
      );
      await manager.saveAgent(agent);

      final built = await ConfiguredAgentFactory(manager).createAgent(agent);
      expect(built.name, 'Helper');
    });
  });
}

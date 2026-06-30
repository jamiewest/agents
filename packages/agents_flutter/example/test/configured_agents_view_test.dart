// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents_flutter/agents_flutter.dart';
import 'package:agents_flutter_example/ui/views/configured_agents/configured_agents.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ConfiguredAgentsManager _buildManager() {
  final kv = InMemoryKeyValueStore();
  return ConfiguredAgentsManager(
    sources: ModelSourceStore(kv),
    agents: AgentConfigurationStore(kv),
    secrets: InMemorySecretStore(),
  );
}

Widget _host(
  ConfiguredAgentsManager manager, {
  void Function(SavedAgentConfig)? onAgentSelected,
}) => MaterialApp(
  home: Scaffold(
    body: ConfiguredAgentsView(
      manager: manager,
      onAgentSelected: onAgentSelected,
    ),
  ),
);

void main() {
  testWidgets('creates a source through the editor', (tester) async {
    final manager = _buildManager();
    await tester.pumpWidget(_host(manager));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add source'));
    await tester.pumpAndSettle();

    // Fields in order: display name (0), endpoint (1), API key (2).
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'My OpenAI');
    await tester.enterText(fields.at(2), 'sk-123');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('My OpenAI'), findsOneWidget);
    final sources = await manager.sources.listSources();
    expect(sources.single.displayName, 'My OpenAI');
    // The key was routed to the secret store, not the config.
    expect(await manager.getSourceApiKey(sources.single.id), 'sk-123');
  });

  testWidgets('changing the provider dropdown persists', (tester) async {
    final manager = _buildManager();
    await tester.pumpWidget(_host(manager));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add source'));
    await tester.pumpAndSettle();

    // Open the provider dropdown (showing its current value) and pick another.
    await tester.tap(find.text('OpenAI-compatible'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anthropic').last);
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Claude source');
    await tester.enterText(fields.at(2), 'sk-ant');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final source = (await manager.sources.listSources()).single;
    expect(source.providerType, ProviderType.anthropic);
  });

  testWidgets('blocked source delete offers cascade', (tester) async {
    final manager = _buildManager();
    await manager.saveSource(
      const ModelSourceConfig(
        id: 's1',
        providerType: ProviderType.openAiCompatible,
        displayName: 'Source A',
      ),
      apiKey: 'sk-1',
    );
    await manager.saveModel(
      const ModelConfig(id: 'm1', sourceId: 's1', modelId: 'gpt'),
    );

    await tester.pumpWidget(_host(manager));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    // The block dialog explains why and offers a force-delete.
    expect(find.textContaining('model'), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, 'Delete anyway'));
    await tester.pumpAndSettle();

    expect(await manager.sources.listSources(), isEmpty);
    expect(await manager.sources.listModels(), isEmpty);
  });

  testWidgets('selecting an agent fires the callback', (tester) async {
    final manager = _buildManager();
    await manager.saveSource(
      const ModelSourceConfig(
        id: 's1',
        providerType: ProviderType.anthropic,
        displayName: 'Anthropic',
      ),
      apiKey: 'sk-1',
    );
    await manager.saveModel(
      const ModelConfig(id: 'm1', sourceId: 's1', modelId: 'claude'),
    );
    await manager.saveAgent(
      const SavedAgentConfig(id: 'a1', name: 'Helper', modelId: 'm1'),
    );

    SavedAgentConfig? selected;
    await tester.pumpWidget(
      _host(manager, onAgentSelected: (agent) => selected = agent),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Helper'));
    await tester.pumpAndSettle();

    expect(selected?.id, 'a1');
  });
}

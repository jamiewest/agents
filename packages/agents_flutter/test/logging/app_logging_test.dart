// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The session-serialization overrides must repeat the upstream
// `jsonSerializerOptions` named parameter.
// ignore_for_file: non_constant_identifier_names

import 'package:agents/agents.dart';
import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLogStore', () {
    test('evicts oldest records beyond capacity', () {
      // Arrange
      final store = AppLogStore(capacity: 2);

      // Act
      for (var i = 0; i < 3; i++) {
        store.add(
          AppLogRecord(
            timestamp: DateTime(2026, 1, 1, 0, 0, i),
            level: LogLevel.information,
            category: 'Test',
            message: 'message $i',
          ),
        );
      }

      // Assert
      expect(store.records, hasLength(2));
      expect(store.records.first.message, 'message 1');
      expect(store.records.last.message, 'message 2');
    });

    test('tracks categories and notifies listeners', () {
      // Arrange
      final store = AppLogStore();
      var notifications = 0;
      store.addListener(() => notifications++);

      // Act
      store.add(
        AppLogRecord(
          timestamp: DateTime(2026),
          level: LogLevel.debug,
          category: 'B',
          message: 'b',
        ),
      );
      store.add(
        AppLogRecord(
          timestamp: DateTime(2026),
          level: LogLevel.debug,
          category: 'A',
          message: 'a',
        ),
      );

      // Assert
      expect(store.categories.toList(), ['A', 'B']);
      expect(notifications, 2);

      // Act
      store.clear();

      // Assert
      expect(store.records, isEmpty);
      expect(store.categories, isEmpty);
      expect(notifications, 3);
    });
  });

  group('LoggingSettings', () {
    test('category overrides match exact and dotted sub-categories', () async {
      // Arrange
      final settings = LoggingSettings();
      await settings.setCategoryLevel('Agents', LogLevel.trace);

      // Assert
      expect(settings.levelFor('Agents'), LogLevel.trace);
      expect(settings.levelFor('Agents.Traffic'), LogLevel.trace);
      expect(settings.levelFor('AgentsX'), LogLevel.information);
      expect(settings.levelFor('Other'), LogLevel.information);
    });

    test('longest matching override wins', () async {
      // Arrange
      final settings = LoggingSettings();
      await settings.setCategoryLevel('Agents', LogLevel.trace);
      await settings.setCategoryLevel('Agents.Traffic', LogLevel.none);

      // Assert
      expect(settings.levelFor('Agents.Traffic'), LogLevel.none);
      expect(settings.isEnabled('Agents.Traffic', LogLevel.critical), isFalse);
      expect(settings.isEnabled('Agents.Other', LogLevel.trace), isTrue);
    });

    test('persists and reloads through a KeyValueStore', () async {
      // Arrange
      final keyValueStore = InMemoryKeyValueStore();
      final settings = LoggingSettings();
      await settings.bindStore(keyValueStore);

      // Act
      await settings.setMinimumLevel(LogLevel.warning);
      await settings.setCategoryLevel('Noisy', LogLevel.none);
      final reloaded = LoggingSettings();
      await reloaded.bindStore(keyValueStore);

      // Assert
      expect(reloaded.minimumLevel, LogLevel.warning);
      expect(reloaded.categoryLevels, {'Noisy': LogLevel.none});
    });

    test('changes made before bindStore completes win over the load', () async {
      // Arrange: the store holds previously persisted values.
      final keyValueStore = InMemoryKeyValueStore();
      final earlier = LoggingSettings();
      await earlier.bindStore(keyValueStore);
      await earlier.setMinimumLevel(LogLevel.error);
      await earlier.setCategoryLevel('Old', LogLevel.none);

      // Act: a settings UI changes values while the loader's bindStore is
      // still reading the persisted state.
      final settings = LoggingSettings();
      final binding = settings.bindStore(keyValueStore);
      await settings.setMinimumLevel(LogLevel.trace);
      await settings.setCategoryLevel('Fresh', LogLevel.debug);
      await binding;

      // Assert: the startup-window changes survive and were persisted.
      expect(settings.minimumLevel, LogLevel.trace);
      expect(settings.categoryLevels, {'Fresh': LogLevel.debug});
      final reloaded = LoggingSettings();
      await reloaded.bindStore(keyValueStore);
      expect(reloaded.minimumLevel, LogLevel.trace);
      expect(reloaded.categoryLevels, {'Fresh': LogLevel.debug});
    });
  });

  group('addAppLogging', () {
    test('settings gate the pipeline at log time', () async {
      // Arrange
      final services = ServiceCollection()
        ..addLogging()
        ..addAppLogging();
      final provider = services.buildServiceProvider();
      final store = provider.getRequiredService<AppLogStore>();
      final settings = provider.getRequiredService<LoggingSettings>();
      final logger = provider.getRequiredService<LoggerFactory>().createLogger(
        'Pipeline',
      );

      // Act: default minimum is information.
      logger.logDebug('dropped');
      logger.logInformation('kept');

      // Assert
      expect(store.records.map((r) => r.message), ['kept']);
      expect(logger.isEnabled(LogLevel.trace), isFalse);

      // Act: lowering the level applies without rebuilding the factory.
      await settings.setMinimumLevel(LogLevel.trace);
      logger.logTrace('now visible');

      // Assert
      expect(logger.isEnabled(LogLevel.trace), isTrue);
      expect(store.records.map((r) => r.message), ['kept', 'now visible']);

      // Act: a category can be silenced entirely.
      await settings.setCategoryLevel('Pipeline', LogLevel.none);
      logger.logError('silenced');

      // Assert
      expect(store.records, hasLength(2));
    });
  });

  group('AgentTrafficLoggingAgent', () {
    test('logs one summary per streamed run, never per update', () async {
      // Arrange
      final store = AppLogStore();
      final logger = AppLogStoreLoggerProvider(
        store,
      ).createLogger(agentTrafficLogCategory);
      final agent = AgentTrafficLoggingAgent(
        _FakeAgent(updates: ['Hel', 'lo ', 'world']),
        logger,
      );

      // Act
      final updates = await agent.runCoreStreaming([
        ChatMessage.fromText(ChatRole.user, 'hi'),
      ]).toList();

      // Assert
      expect(updates, hasLength(3));
      expect(store.records, hasLength(2));
      expect(store.records.first.message, contains('run started'));
      expect(store.records.last.message, contains('3 updates'));
      expect(store.records.last.message, contains('Hello world'));
    });

    test('logs a summary for non-streaming runs', () async {
      // Arrange
      final store = AppLogStore();
      final logger = AppLogStoreLoggerProvider(
        store,
      ).createLogger(agentTrafficLogCategory);
      final agent = AgentTrafficLoggingAgent(
        _FakeAgent(updates: ['ok']),
        logger,
      );

      // Act
      final response = await agent.runCore([
        ChatMessage.fromText(ChatRole.user, 'hi'),
      ]);

      // Assert
      expect(response.text, 'ok');
      expect(store.records, hasLength(2));
      expect(store.records.last.message, contains('responded in'));
    });

    test('logs a terminator when the consumer cancels the stream', () async {
      // Arrange
      final store = AppLogStore();
      final logger = AppLogStoreLoggerProvider(
        store,
      ).createLogger(agentTrafficLogCategory);
      final agent = AgentTrafficLoggingAgent(
        _FakeAgent(updates: ['Hel', 'lo ', 'world']),
        logger,
      );

      // Act: take one update, then cancel mid-run.
      final update = await agent.runCoreStreaming([
        ChatMessage.fromText(ChatRole.user, 'hi'),
      ]).first;
      await pumpEventQueue();

      // Assert: the started line still gets exactly one terminator.
      expect(update, isNotNull);
      expect(store.records, hasLength(2));
      expect(store.records.first.message, contains('run started'));
      expect(store.records.last.message, contains('run cancelled'));
    });

    test('logs and rethrows failures', () async {
      // Arrange
      final store = AppLogStore();
      final logger = AppLogStoreLoggerProvider(
        store,
      ).createLogger(agentTrafficLogCategory);
      final agent = AgentTrafficLoggingAgent(_FakeAgent(fail: true), logger);

      // Act + Assert
      await expectLater(
        agent.runCore([ChatMessage.fromText(ChatRole.user, 'hi')]),
        throwsStateError,
      );
      expect(store.records.last.level, LogLevel.error);
      expect(store.records.last.message, contains('run failed'));
    });
  });
}

class _FakeAgent extends AIAgent {
  _FakeAgent({this.updates = const [], this.fail = false});

  final List<String> updates;
  final bool fail;

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _FakeSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => null;

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _FakeSession();

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    if (fail) throw StateError('boom');
    return AgentResponse(
      message: ChatMessage.fromText(ChatRole.assistant, updates.join()),
    );
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    if (fail) throw StateError('boom');
    for (final update in updates) {
      yield AgentResponseUpdate(role: ChatRole.assistant, content: update);
    }
  }
}

class _FakeSession extends AgentSession {
  _FakeSession() : super(AgentSessionStateBag(null));
}

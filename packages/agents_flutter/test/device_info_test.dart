// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents/agents.dart';
import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceInfo', () {
    test('reports not-ready fallbacks before population', () {
      final info = DeviceInfo();

      expect(info.isReady, isFalse);
      expect(info.displayName, 'This device');
      expect(info.summary, isNull);
      expect(info.describe(), contains('not available yet'));
    });

    test('falls back through the platform name keys', () {
      DeviceInfo populated(Map<String, String> fields) =>
          DeviceInfo()..populate(fields);

      expect(
        populated({'Device': 'Pixel 9', 'Model': 'GX7'}).displayName,
        'Pixel 9',
      );
      expect(populated({'Computer': 'Studio'}).displayName, 'Studio');
      expect(populated({'Model': 'MacBook Pro'}).displayName, 'MacBook Pro');
      expect(populated({'System': 'Linux'}).displayName, 'Linux');
      expect(populated({'Cores': '8'}).displayName, 'This device');
    });

    test('summary combines the display name with the system', () {
      final full = DeviceInfo()
        ..populate({'Computer': 'Studio', 'System': 'macOS 15.5'});
      final bare = DeviceInfo()..populate({'Computer': 'Studio'});

      expect(full.summary, 'Studio, macOS 15.5');
      expect(bare.summary, 'Studio');
    });

    test('describe renders key: value lines', () {
      final info = DeviceInfo()
        ..populate({'Device': 'Pixel 9', 'System': 'Android 16'});

      expect(info.describe(), 'Device: Pixel 9\nSystem: Android 16');
    });
  });

  group('DeviceContextProvider', () {
    test('emits nothing until gathered, then a stable one-liner', () async {
      final info = DeviceInfo();
      final provider = DeviceContextProvider(info);

      final before = await provider.invoking(_invokingContext());
      info.populate({'Computer': 'Studio', 'System': 'macOS 15.5'});
      final after = await provider.invoking(_invokingContext());

      expect(before.instructions, isNull);
      expect(after.instructions, 'Device: Studio, macOS 15.5');
    });
  });

  group('get_device_info tool', () {
    test('reads the cache and reports not-available before it', () async {
      final info = DeviceInfo();
      final tool = createGetDeviceInfoTool(info);

      expect(tool.name, 'get_device_info');
      expect(
        await tool.invoke(AIFunctionArguments()),
        contains('not available yet'),
      );

      info.populate({'Device': 'Pixel 9'});
      expect(await tool.invoke(AIFunctionArguments()), 'Device: Pixel 9');
    });
  });

  group('AppInfo', () {
    test('describe reports not-available before population', () {
      final info = AppInfo();

      expect(info.isReady, isFalse);
      expect(info.describe(), contains('not available yet'));
    });

    test('populate exposes typed fields and a describe block', () {
      final info = AppInfo()
        ..populate(
          appName: 'Agents',
          packageName: 'dev.jamiewest.agents',
          version: '1.4.0',
          buildNumber: '42',
        );

      expect(info.isReady, isTrue);
      expect(info.appName, 'Agents');
      expect(info.packageName, 'dev.jamiewest.agents');
      expect(info.version, '1.4.0');
      expect(info.buildNumber, '42');
      expect(
        info.describe(),
        'App name: Agents\n'
        'Package id: dev.jamiewest.agents\n'
        'Version: 1.4.0\n'
        'Build number: 42',
      );
    });
  });

  group('get_app_info tool', () {
    test('reads the cache and reports not-available before it', () async {
      final info = AppInfo();
      final tool = createGetAppInfoTool(info);

      expect(tool.name, 'get_app_info');
      expect(
        await tool.invoke(AIFunctionArguments()),
        contains('not available yet'),
      );

      info.populate(
        appName: 'Agents',
        packageName: 'dev.jamiewest.agents',
        version: '1.4.0',
        buildNumber: '42',
      );
      expect(await tool.invoke(AIFunctionArguments()), contains('Agents'));
    });
  });
}

InvokingContext _invokingContext() =>
    InvokingContext(_TestAgent(), null, null, AIContext());

class _TestAgent extends AIAgent {
  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) => throw UnimplementedError();
}

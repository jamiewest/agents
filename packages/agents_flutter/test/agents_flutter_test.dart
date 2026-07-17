// ignore_for_file: non_constant_identifier_names

import 'dart:async';

import 'package:agents/agents.dart';
import 'package:agents_flutter/agents_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:extensions/system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectivityContextProvider', () {
    test('adds offline marker when the monitor reports offline', () async {
      final provider = await _provider([ConnectivityResult.none]);

      final result = await provider.invoking(_createInvokingContext());

      expect(result.instructions, contains('offline'));
      expect(result.instructions, contains('network-dependent tools'));
    });

    test('treats an empty connectivity result as offline', () async {
      final provider = await _provider(const []);

      final result = await provider.invoking(_createInvokingContext());

      expect(result.instructions, contains('offline'));
    });

    test('adds no marker when an active interface is reported', () async {
      for (final results in [
        [ConnectivityResult.wifi],
        [ConnectivityResult.mobile],
        [ConnectivityResult.wifi, ConnectivityResult.mobile],
        [ConnectivityResult.none, ConnectivityResult.ethernet],
      ]) {
        final provider = await _provider(results);

        final result = await provider.invoking(_createInvokingContext());

        expect(result.instructions, isNull);
      }
    });

    test('adds no marker while the state is unknown', () async {
      final monitor = ConnectivityMonitor(
        checkConnectivity: () async => throw StateError('check failed'),
        onChanged: const Stream.empty(),
      );
      await _settle();
      final provider = ConnectivityContextProvider(monitor);

      final result = await provider.invoking(_createInvokingContext());

      expect(result.instructions, isNull);
    });

    test('merges the offline marker with existing instructions', () async {
      final provider = await _provider([ConnectivityResult.none]);
      final context = _createInvokingContext(
        instructions: 'Existing instructions.',
      );

      final result = await provider.invoking(context);

      expect(result.instructions, startsWith('Existing instructions.\n'));
      expect(result.instructions, contains('offline'));
    });

    test('reflects a connectivity change from the monitor stream', () async {
      final controller = StreamController<List<ConnectivityResult>>();
      final monitor = ConnectivityMonitor(
        checkConnectivity: () async => [ConnectivityResult.wifi],
        onChanged: controller.stream,
      );
      await _settle();
      final provider = ConnectivityContextProvider(monitor);

      final online = await provider.invoking(_createInvokingContext());
      expect(online.instructions, isNull);

      controller.add([ConnectivityResult.none]);
      await _settle();

      final offline = await provider.invoking(_createInvokingContext());
      expect(offline.instructions, contains('offline'));

      await controller.close();
      monitor.dispose();
    });

    test('a slow seed never overwrites a newer stream event', () async {
      final controller = StreamController<List<ConnectivityResult>>();
      final seed = Completer<List<ConnectivityResult>>();
      final monitor = ConnectivityMonitor(
        checkConnectivity: () => seed.future,
        onChanged: controller.stream,
      );
      final provider = ConnectivityContextProvider(monitor);

      // The device goes offline while the seed poll is still in flight; the
      // poll's stale online snapshot must not win when it finally lands.
      controller.add([ConnectivityResult.none]);
      await _settle();
      seed.complete([ConnectivityResult.wifi]);
      await _settle();

      final result = await provider.invoking(_createInvokingContext());
      expect(result.instructions, contains('offline'));

      await controller.close();
      monitor.dispose();
    });
  });

  group('get_connectivity', () {
    test('reports the active connection types', () async {
      final tool = createConnectivityTool(
        checkConnectivity: () async => [ConnectivityResult.wifi],
      );

      expect(tool.name, 'get_connectivity');
      expect(await tool.invoke(AIFunctionArguments()), 'Connected via: wifi');
    });

    test('reports offline when there is no connection', () async {
      final tool = createConnectivityTool(
        checkConnectivity: () async => [ConnectivityResult.none],
      );

      expect(
        await tool.invoke(AIFunctionArguments()),
        'No network connection (offline).',
      );
    });
  });

  group('registration', () {
    test('registers the monitor, provider alias, and tool', () {
      final monitor = _fakeMonitor([ConnectivityResult.none]);
      final services = ServiceCollection()
        ..addSingletonInstance<ConnectivityMonitor>(monitor)
        ..addConnectivityContextProvider();
      final serviceProvider = services.buildServiceProvider();

      expect(
        serviceProvider.getRequiredService<ConnectivityMonitor>(),
        same(monitor),
      );
      expect(
        serviceProvider.getServices<AIContextProvider>().single,
        isA<ConnectivityContextProvider>(),
      );
      expect(
        serviceProvider.getServices<AITool>().single.name,
        'get_connectivity',
      );
    });

    test('omits the tool when requested', () {
      final services = ServiceCollection()
        ..addSingletonInstance<ConnectivityMonitor>(
          _fakeMonitor([ConnectivityResult.wifi]),
        )
        ..addConnectivityContextProvider(includeConnectivityTool: false);
      final serviceProvider = services.buildServiceProvider();

      expect(serviceProvider.getServices<AITool>(), isEmpty);
    });

    test('options helper preserves existing providers and tools', () {
      final existingProvider = ConnectivityContextProvider(
        _fakeMonitor([ConnectivityResult.wifi]),
      );
      final existingTool = AIFunctionFactory.create(
        name: 'existing_tool',
        callback: (_, {cancellationToken}) async => null,
      );
      final options = ChatClientAgentOptions()
        ..chatOptions = ChatOptions(temperature: 0.25, tools: [existingTool])
        ..aiContextProviders = [existingProvider];

      final returned = options.addConnectivityContextProvider(
        monitor: _fakeMonitor([ConnectivityResult.none]),
      );

      expect(returned, same(options));
      expect(options.aiContextProviders, hasLength(2));
      expect(options.aiContextProviders!.first, same(existingProvider));
      expect(options.chatOptions!.temperature, 0.25);
      expect(options.chatOptions!.tools!.first, same(existingTool));
      expect(options.chatOptions!.tools!.last.name, 'get_connectivity');
    });
  });
}

Future<ConnectivityContextProvider> _provider(
  List<ConnectivityResult> results,
) async {
  final monitor = _fakeMonitor(results);
  await _settle();
  return ConnectivityContextProvider(monitor);
}

ConnectivityMonitor _fakeMonitor(List<ConnectivityResult> results) {
  return ConnectivityMonitor(
    checkConnectivity: () async => results,
    onChanged: const Stream.empty(),
  );
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

InvokingContext _createInvokingContext({String? instructions}) {
  return InvokingContext(
    _TestAgent(),
    null,
    null,
    AIContext()..instructions = instructions,
  );
}

class _TestAgent extends AIAgent {
  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }
}

import 'package:agents/agents.dart';
import 'package:agents_flutter/agents_flutter.dart';
import 'package:agents_flutter/src/flutter_harness_platform_defaults.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:extensions/ai.dart';
import 'package:extensions_flutter/extensions_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The direct FlutterHarnessAgent path constructs a real ConnectivityMonitor,
  // whose event-channel subscription needs the Flutter test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  ConnectivityMonitor fakeMonitor() => ConnectivityMonitor(
    onChanged: const Stream<List<ConnectivityResult>>.empty(),
    checkConnectivity: () async => [ConnectivityResult.wifi],
  );

  FlutterHarnessCapabilities build(FlutterHarnessAgentOptions options) =>
      buildFlutterHarnessCapabilities(
        options,
        clock: Clock.fixed(DateTime.utc(2026, 6, 28)),
        connectivityMonitor: fakeMonitor(),
        deviceInfo: DeviceInfo(),
        appInfo: AppInfo(),
        locationResolver: LocationResolver(),
      );

  List<String> typeNames(List<AIContextProvider> providers) =>
      providers.map((p) => p.runtimeType.toString()).toList();

  List<String> toolNames(List<AITool> tools) =>
      tools.map((t) => t.name).toList();

  group('buildFlutterHarnessCapabilities', () {
    test('includes the safe-core capabilities by default', () {
      final result = build(FlutterHarnessAgentOptions());

      expect(typeNames(result.providers), [
        'TemporalContextProvider',
        'DeviceContextProvider',
        'ConnectivityContextProvider',
      ]);
      expect(toolNames(result.tools), [
        'get_current_time',
        'get_device_info',
        'get_app_info',
        'get_connectivity',
      ]);
    });

    test('app info contributes a tool but no provider', () {
      final result = build(
        FlutterHarnessAgentOptions()
          ..enableTemporal = false
          ..enableDeviceInfo = false
          ..enableConnectivity = false,
      );

      expect(result.providers, isEmpty);
      expect(toolNames(result.tools), ['get_app_info']);
    });

    test('location opt-in adds a provider and two tools', () {
      final result = build(
        FlutterHarnessAgentOptions()
          ..enableTemporal = false
          ..enableDeviceInfo = false
          ..enableAppInfo = false
          ..enableConnectivity = false
          ..enableLocation = true,
      );

      expect(typeNames(result.providers), ['LocationContextProvider']);
      expect(toolNames(result.tools), [
        'get_current_location',
        'geocode_address',
      ]);
    });

    test('network opt-in adds a provider and tool', () {
      final result = build(
        FlutterHarnessAgentOptions()
          ..enableTemporal = false
          ..enableDeviceInfo = false
          ..enableAppInfo = false
          ..enableConnectivity = false
          ..enableNetworkInfo = true,
      );

      expect(typeNames(result.providers), ['NetworkContextProvider']);
      expect(toolNames(result.tools), ['get_current_network_info']);
    });

    test('wake-lock opt-in adds a tool only', () {
      final result = build(
        FlutterHarnessAgentOptions()
          ..enableTemporal = false
          ..enableDeviceInfo = false
          ..enableAppInfo = false
          ..enableConnectivity = false
          ..enableWakeLock = true,
      );

      expect(result.providers, isEmpty);
      expect(toolNames(result.tools), ['set_wake_lock']);
    });

    test('connectivity stays last with every capability enabled', () {
      final result = build(
        FlutterHarnessAgentOptions()
          ..enableLocation = true
          ..enableNetworkInfo = true
          ..enableWakeLock = true,
      );

      expect(result.providers.last, isA<ConnectivityContextProvider>());
      expect(toolNames(result.tools).last, 'get_connectivity');
    });

    test('disabling a safe-core capability omits it', () {
      final result = build(
        FlutterHarnessAgentOptions()..enableConnectivity = false,
      );

      expect(
        typeNames(result.providers),
        isNot(contains('ConnectivityContextProvider')),
      );
      expect(toolNames(result.tools), isNot(contains('get_connectivity')));
    });
  });

  group('addFlutterHarnessContext', () {
    test('appends capabilities while preserving existing providers/tools', () {
      final existingProvider = _MarkerProvider();
      final existingTool = AIFunctionFactory.create(
        name: 'existing_tool',
        callback: (_, {cancellationToken}) async => null,
      );
      final options = ChatClientAgentOptions()
        ..aiContextProviders = [existingProvider]
        ..chatOptions = (ChatOptions()..tools = [existingTool]);

      options.addFlutterHarnessContext(
        connectivityMonitor: fakeMonitor(),
        deviceInfo: DeviceInfo(),
        appInfo: AppInfo(),
      );

      expect(options.aiContextProviders!.first, same(existingProvider));
      expect(options.chatOptions!.tools!.first, same(existingTool));
      expect(
        options.aiContextProviders!.whereType<ConnectivityContextProvider>(),
        isNotEmpty,
      );
      expect(toolNames(options.chatOptions!.tools!.toList()), [
        'existing_tool',
        'get_current_time',
        'get_device_info',
        'get_app_info',
        'get_connectivity',
      ]);
    });

    test('honors opt-in flags', () {
      final options = ChatClientAgentOptions();

      options.addFlutterHarnessContext(
        enableTemporal: false,
        enableDeviceInfo: false,
        enableAppInfo: false,
        enableConnectivity: false,
        enableWakeLock: true,
        connectivityMonitor: fakeMonitor(),
        deviceInfo: DeviceInfo(),
        appInfo: AppInfo(),
      );

      expect(options.aiContextProviders, isEmpty);
      expect(toolNames(options.chatOptions!.tools!.toList()), [
        'set_wake_lock',
      ]);
    });
  });

  group('FlutterHarnessAgent', () {
    test('merges into a clone without mutating the caller options', () {
      final marker = _MarkerProvider();
      final options = FlutterHarnessAgentOptions()
        ..harnessInstructions = 'custom harness instructions'
        ..aiContextProviders = [marker];

      FlutterHarnessAgent(_FakeChatClient(), 1000, 100, options: options);

      // Capabilities are appended to a private clone, so the caller's options
      // is untouched: no Flutter providers appended, no chatOptions created.
      expect(options.harnessInstructions, 'custom harness instructions');
      expect(options.aiContextProviders, [marker]);
      expect(options.chatOptions, isNull);
    });
  });

  group('FlutterHarnessAgentOptions.clone', () {
    test('preserves standard options and capability flags', () {
      final marker = _MarkerProvider();
      final original =
          FlutterHarnessAgentOptions(
              enableConnectivity: false,
              enableLocation: true,
              timeZoneId: 'Asia/Tokyo',
            )
            ..harnessInstructions = 'keep me'
            ..aiContextProviders = [marker]
            ..chatOptions = (ChatOptions()..temperature = 0.25);

      final copy = original.clone();

      expect(copy.harnessInstructions, 'keep me');
      expect(copy.enableConnectivity, isFalse);
      expect(copy.enableLocation, isTrue);
      expect(copy.timeZoneId, 'Asia/Tokyo');
      expect(copy.aiContextProviders, [marker]);
      expect(copy.chatOptions!.temperature, 0.25);
    });

    test('isolates the provider list and chatOptions from the original', () {
      final original = FlutterHarnessAgentOptions()
        ..aiContextProviders = [_MarkerProvider()]
        ..chatOptions = ChatOptions();

      final copy = original.clone();
      (copy.aiContextProviders! as List<AIContextProvider>).add(
        _MarkerProvider(),
      );
      copy.chatOptions!.tools = [
        AIFunctionFactory.create(
          name: 't',
          callback: (_, {cancellationToken}) async => null,
        ),
      ];

      expect(original.aiContextProviders, hasLength(1));
      expect(original.chatOptions!.tools, isNull);
    });
  });

  group('applyFlutterHarnessPlatformDefaults', () {
    test('uses in-memory stores and skills on web', () {
      final options = FlutterHarnessAgentOptions();

      applyFlutterHarnessPlatformDefaults(options, isWeb: true);

      expect(options.fileMemoryStore, isA<InMemoryAgentFileStore>());
      expect(options.fileAccessStore, isA<InMemoryAgentFileStore>());
      expect(options.agentSkillsSource, isA<AgentInMemorySkillsSource>());
    });

    test('preserves explicit web stores, sources, and disabled features', () {
      final memoryStore = InMemoryAgentFileStore();
      final accessStore = InMemoryAgentFileStore();
      final skillsSource = AgentInMemorySkillsSource(const []);
      final disabled = FlutterHarnessAgentOptions()
        ..disableFileMemory = true
        ..disableFileAccess = true
        ..disableAgentSkillsProvider = true;
      final configured = FlutterHarnessAgentOptions()
        ..fileMemoryStore = memoryStore
        ..fileAccessStore = accessStore
        ..agentSkillsSource = skillsSource;

      applyFlutterHarnessPlatformDefaults(disabled, isWeb: true);
      applyFlutterHarnessPlatformDefaults(configured, isWeb: true);

      expect(disabled.fileMemoryStore, isNull);
      expect(disabled.fileAccessStore, isNull);
      expect(disabled.agentSkillsSource, isNull);
      expect(configured.fileMemoryStore, same(memoryStore));
      expect(configured.fileAccessStore, same(accessStore));
      expect(configured.agentSkillsSource, same(skillsSource));
    });

    test('leaves non-web defaults unchanged', () {
      final options = FlutterHarnessAgentOptions();

      applyFlutterHarnessPlatformDefaults(options, isWeb: false);

      expect(options.fileMemoryStore, isNull);
      expect(options.fileAccessStore, isNull);
      expect(options.agentSkillsSource, isNull);
    });
  });

  group('addFlutterHarness (dependency injection)', () {
    test('registers app/device info, hosted services, and an agent', () {
      final services = ServiceCollection()
        ..addSingletonInstance<ChatClient>(_FakeChatClient())
        ..addSingletonInstance<ConnectivityMonitor>(fakeMonitor())
        ..addFlutterHarness();
      final provider = services.buildServiceProvider();

      expect(provider.getRequiredService<AppInfo>(), isNotNull);
      expect(provider.getRequiredService<DeviceInfo>(), isNotNull);

      final hosted = provider.getServices<HostedService>().toList();
      expect(hosted.whereType<PackageInfoHostedService>(), isNotEmpty);
      expect(hosted.whereType<DeviceInfoHostedService>(), isNotEmpty);

      expect(provider.getRequiredService<AIAgent>(), isNotNull);
    });

    test('opt-in flags register location and network services', () {
      final services = ServiceCollection()
        ..addSingletonInstance<ChatClient>(_FakeChatClient())
        ..addSingletonInstance<ConnectivityMonitor>(fakeMonitor())
        ..addFlutterHarness(
          configure: (options) => options
            ..enableLocation = true
            ..enableNetworkInfo = true,
        );
      final provider = services.buildServiceProvider();

      expect(provider.getRequiredService<LocationResolver>(), isNotNull);
      expect(provider.getRequiredService<NetworkInfoSource>(), isNotNull);
    });

    test('preserves a pre-registered ConnectivityMonitor', () {
      final monitor = fakeMonitor();
      final services = ServiceCollection()
        ..addSingletonInstance<ChatClient>(_FakeChatClient())
        ..addSingletonInstance<ConnectivityMonitor>(monitor)
        ..addFlutterHarness();
      final provider = services.buildServiceProvider();

      expect(provider.getRequiredService<ConnectivityMonitor>(), same(monitor));
    });

    test('useFlutterHarnessAgent registers via addFlutter', () {
      final services = ServiceCollection()
        ..addSingletonInstance<ChatClient>(_FakeChatClient())
        ..addSingletonInstance<ConnectivityMonitor>(fakeMonitor())
        ..addFlutter((flutter) => flutter.useFlutterHarnessAgent());
      final provider = services.buildServiceProvider();

      final hosted = provider.getServices<HostedService>().toList();
      expect(hosted.whereType<DeviceInfoHostedService>(), isNotEmpty);
      expect(provider.getRequiredService<AIAgent>(), isNotNull);
    });
  });
}

final class _MarkerProvider extends AIContextProvider {
  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async => AIContext();
}

final class _FakeChatClient implements ChatClient {
  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async => ChatResponse.fromMessage(
    ChatMessage.fromText(ChatRole.assistant, 'response'),
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

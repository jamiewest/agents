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

    test('network opt-in adds the tool only, never the provider', () {
      final result = build(
        FlutterHarnessAgentOptions()
          ..enableTemporal = false
          ..enableDeviceInfo = false
          ..enableAppInfo = false
          ..enableConnectivity = false
          ..enableNetworkInfo = true,
      );

      // The provider's per-turn platform reads and volatile values would
      // break KV-prefix caching; the harness only ever wires the tool.
      expect(result.providers, isEmpty);
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

    test('a pushover client adds the send and quota tools, no provider', () {
      final result = build(
        FlutterHarnessAgentOptions()
          ..enableTemporal = false
          ..enableDeviceInfo = false
          ..enableAppInfo = false
          ..enableConnectivity = false
          ..pushoverClient = PushoverClient(token: 'app-token', user: 'user'),
      );

      expect(result.providers, isEmpty);
      expect(toolNames(result.tools), [
        'send_pushover_notification',
        'get_pushover_limits',
      ]);
    });

    test('pushover tool options select the quota and receipt tools', () {
      final result = build(
        FlutterHarnessAgentOptions()
          ..enableTemporal = false
          ..enableDeviceInfo = false
          ..enableAppInfo = false
          ..enableConnectivity = false
          ..pushoverClient = PushoverClient(token: 'app-token', user: 'user')
          ..pushoverToolOptions = (PushoverToolOptions()
            ..includeLimitsTool = false
            ..allowEmergencyPriority = true),
      );

      expect(toolNames(result.tools), [
        'send_pushover_notification',
        'check_pushover_receipt',
      ]);
    });

    test('no pushover client, no pushover tools', () {
      final result = build(FlutterHarnessAgentOptions());

      expect(
        toolNames(result.tools),
        isNot(contains('send_pushover_notification')),
      );
    });

    test('a local search source adds search and page-opening tools', () {
      final result = build(
        FlutterHarnessAgentOptions(webSearchSource: _FakeWebSearchSource()),
      );

      expect(
        toolNames(result.tools),
        containsAll(<String>[webSearchToolName, openWebPageToolName]),
      );
    });

    test('a page loader alone adds only open_web_page', () {
      final result = build(
        FlutterHarnessAgentOptions(webPageLoader: _FakeWebPageLoader()),
      );

      expect(toolNames(result.tools), contains(openWebPageToolName));
      expect(toolNames(result.tools), isNot(contains(webSearchToolName)));
    });

    test('disableWebSearch suppresses configured local web tools', () {
      final result = build(
        FlutterHarnessAgentOptions(
          webSearchSource: _FakeWebSearchSource(),
          webPageLoader: _FakeWebPageLoader(),
        )..disableWebSearch = true,
      );

      expect(toolNames(result.tools), isNot(contains(webSearchToolName)));
      expect(toolNames(result.tools), isNot(contains(openWebPageToolName)));
    });

    test('connectivity stays last with every capability enabled', () {
      final result = build(
        FlutterHarnessAgentOptions()
          ..enableLocation = true
          ..enableNetworkInfo = true
          ..enableWakeLock = true
          ..pushoverClient = PushoverClient(token: 'app-token', user: 'user'),
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

    test('requires the monitor/resolver only for enabled capabilities', () {
      FlutterHarnessCapabilities buildBare(FlutterHarnessAgentOptions o) =>
          buildFlutterHarnessCapabilities(
            o,
            clock: Clock.fixed(DateTime.utc(2026, 6, 28)),
            deviceInfo: DeviceInfo(),
            appInfo: AppInfo(),
          );

      expect(
        () => buildBare(FlutterHarnessAgentOptions()),
        throwsArgumentError,
        reason: 'connectivity enabled but no monitor supplied',
      );
      expect(
        () => buildBare(
          FlutterHarnessAgentOptions()
            ..enableConnectivity = false
            ..enableLocation = true,
        ),
        throwsArgumentError,
        reason: 'location enabled but no resolver supplied',
      );

      final result = buildBare(
        FlutterHarnessAgentOptions()..enableConnectivity = false,
      );
      expect(typeNames(result.providers), [
        'TemporalContextProvider',
        'DeviceContextProvider',
      ]);
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

    test('adds local web tools from direct extension arguments', () {
      final options = ChatClientAgentOptions();

      options.addFlutterHarnessContext(
        enableTemporal: false,
        enableConnectivity: false,
        enableAppInfo: false,
        enableDeviceInfo: false,
        webSearchSource: _FakeWebSearchSource(),
        webPageLoader: _FakeWebPageLoader(),
      );

      expect(toolNames(options.chatOptions!.tools!.toList()), <String>[
        webSearchToolName,
        openWebPageToolName,
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

    test('dispose releases owned platform resources', () {
      final agent = FlutterHarnessAgent(_FakeChatClient(), 1000, 100);
      agent.dispose();

      final bare = FlutterHarnessAgent(
        _FakeChatClient(),
        1000,
        100,
        options: FlutterHarnessAgentOptions(
          enableConnectivity: false,
          enableLocation: false,
        ),
      );
      bare.dispose();
    });

    test('local web tools replace the hosted search marker', () {
      final agent = FlutterHarnessAgent(
        _FakeChatClient(),
        1000,
        100,
        options: FlutterHarnessAgentOptions(
          webSearchSource: _FakeWebSearchSource(),
          webPageLoader: _FakeWebPageLoader(),
        ),
      );

      final tools = agent.getServiceOf<ChatOptions>()!.tools!;
      expect(
        toolNames(tools.toList()),
        containsAll(<String>[webSearchToolName, openWebPageToolName]),
      );
      expect(tools.whereType<HostedWebSearchTool>(), isEmpty);
      agent.dispose();
    });

    test('preserves hosted search when local web tools are not configured', () {
      final agent = FlutterHarnessAgent(_FakeChatClient(), 1000, 100);

      final tools = agent.getServiceOf<ChatOptions>()!.tools!;

      expect(tools.whereType<HostedWebSearchTool>(), hasLength(1));
      expect(toolNames(tools.toList()), isNot(contains(openWebPageToolName)));
      agent.dispose();
    });

    test('a page loader adds direct opening and preserves hosted search', () {
      final agent = FlutterHarnessAgent(
        _FakeChatClient(),
        1000,
        100,
        options: FlutterHarnessAgentOptions(
          webPageLoader: _FakeWebPageLoader(),
        ),
      );

      final tools = agent.getServiceOf<ChatOptions>()!.tools!;

      expect(tools.whereType<HostedWebSearchTool>(), hasLength(1));
      expect(toolNames(tools.toList()), contains(openWebPageToolName));
      expect(
        tools.whereType<AIFunction>().where(
          (tool) => tool.name == webSearchToolName,
        ),
        isEmpty,
      );
      agent.dispose();
    });

    test('disabled access exposes neither hosted nor local web tools', () {
      final agent = FlutterHarnessAgent(
        _FakeChatClient(),
        1000,
        100,
        options: FlutterHarnessAgentOptions(
          webSearchSource: _FakeWebSearchSource(),
          webPageLoader: _FakeWebPageLoader(),
        )..disableWebSearch = true,
      );

      final tools = agent.getServiceOf<ChatOptions>()!.tools!;

      expect(tools.whereType<HostedWebSearchTool>(), isEmpty);
      expect(
        tools.whereType<AIFunction>().where(
          (tool) =>
              tool.name == webSearchToolName ||
              tool.name == openWebPageToolName,
        ),
        isEmpty,
      );
      agent.dispose();
    });
  });

  group('FlutterHarnessAgentOptions.clone', () {
    test('preserves standard options and capability flags', () {
      final marker = _MarkerProvider();
      final pushoverClient = PushoverClient(token: 'app-token', user: 'user');
      final pushoverToolOptions = PushoverToolOptions()
        ..allowEmergencyPriority = true;
      final original =
          FlutterHarnessAgentOptions(
              enableConnectivity: false,
              enableLocation: true,
              timeZoneId: 'Asia/Tokyo',
              webSearchSource: _FakeWebSearchSource(),
              webPageLoader: _FakeWebPageLoader(),
            )
            ..harnessInstructions = 'keep me'
            ..aiContextProviders = [marker]
            ..chatOptions = (ChatOptions()..temperature = 0.25)
            ..pushoverClient = pushoverClient
            ..pushoverToolOptions = pushoverToolOptions;

      final copy = original.clone();

      expect(copy.harnessInstructions, 'keep me');
      expect(copy.enableConnectivity, isFalse);
      expect(copy.enableLocation, isTrue);
      expect(copy.timeZoneId, 'Asia/Tokyo');
      expect(copy.aiContextProviders, [marker]);
      expect(copy.chatOptions!.temperature, 0.25);
      expect(copy.pushoverClient, same(pushoverClient));
      expect(copy.pushoverToolOptions, same(pushoverToolOptions));
      expect(copy.webSearchSource, same(original.webSearchSource));
      expect(copy.webPageLoader, same(original.webPageLoader));
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

    test('DI harness replaces hosted search with configured local tools', () {
      final services = ServiceCollection()
        ..addSingletonInstance<ChatClient>(_FakeChatClient())
        ..addSingletonInstance<ConnectivityMonitor>(fakeMonitor())
        ..addFlutterHarness(
          configure: (options) => options
            ..webSearchSource = _FakeWebSearchSource()
            ..webPageLoader = _FakeWebPageLoader(),
        );
      final provider = services.buildServiceProvider();

      final agent = provider.getRequiredService<AIAgent>();
      final tools = agent.getServiceOf<ChatOptions>()!.tools!;

      expect(tools.whereType<HostedWebSearchTool>(), isEmpty);
      expect(
        toolNames(tools.toList()),
        containsAll(<String>[webSearchToolName, openWebPageToolName]),
      );
    });

    test('does not duplicate capabilities across service providers', () {
      late FlutterHarnessAgentOptions registrationOptions;
      final services = ServiceCollection()
        ..addSingletonInstance<ChatClient>(_FakeChatClient())
        ..addSingletonInstance<ConnectivityMonitor>(fakeMonitor())
        ..addFlutterHarness(
          configure: (options) => registrationOptions = options,
        );

      // Resolving from two providers built off the same collection runs the
      // agent factory twice; capabilities must merge into per-agent clones,
      // never into the captured registration options.
      expect(
        services.buildServiceProvider().getRequiredService<AIAgent>(),
        isNotNull,
      );
      expect(
        services.buildServiceProvider().getRequiredService<AIAgent>(),
        isNotNull,
      );

      expect(registrationOptions.aiContextProviders, isNull);
      expect(registrationOptions.chatOptions, isNull);
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

final class _FakeWebSearchSource implements WebSearchSource {
  @override
  Future<Iterable<WebSearchResult>> search(
    String query, {
    required int maxResults,
    CancellationToken? cancellationToken,
  }) async => const <WebSearchResult>[];
}

final class _FakeWebPageLoader implements WebPageLoader {
  @override
  Future<WebPageContent> load(
    Uri url, {
    CancellationToken? cancellationToken,
  }) async => WebPageContent(
    status: WebPageLoadStatus.success,
    requestedUrl: url,
    finalUrl: url,
    text: 'page',
  );
}

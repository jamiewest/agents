// ignore_for_file: non_constant_identifier_names

import 'package:agents/agents.dart';
import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkContextProvider', () {
    test('injects available trimmed network details', () async {
      final provider = NetworkContextProvider(
        source: _FakeNetworkInfoSource(
          wifiName: '  Studio Wi-Fi  ',
          wifiIP: ' 192.168.1.10 ',
          wifiIPv6: ' fe80::1 ',
          wifiSubmask: ' 255.255.255.0 ',
          wifiGatewayIP: ' 192.168.1.1 ',
          wifiBroadcast: ' 192.168.1.255 ',
        ),
      );

      final result = await provider.invoking(_createInvokingContext());

      expect(result.instructions, startsWith('Network context:\n'));
      expect(result.instructions, contains('- Wi-Fi SSID: Studio Wi-Fi'));
      expect(result.instructions, contains('- IPv4 address: 192.168.1.10'));
      expect(result.instructions, contains('- IPv6 address: fe80::1'));
      expect(result.instructions, contains('- Subnet mask: 255.255.255.0'));
      expect(result.instructions, contains('- Gateway IP: 192.168.1.1'));
      expect(
        result.instructions,
        contains('- Broadcast address: 192.168.1.255'),
      );
      expect(result.instructions, contains('local networking'));
      expect(result.messages, isNull);
    });

    test('omits unavailable, blank, and failed fields', () async {
      final provider = NetworkContextProvider(
        source: _FakeNetworkInfoSource(
          wifiName: '  ',
          wifiIP: '10.0.0.8',
          wifiIPv6Error: StateError('unsupported'),
          wifiSubmask: null,
          wifiGatewayIP: '',
          wifiBroadcast: '10.0.0.255',
        ),
      );

      final result = await provider.invoking(_createInvokingContext());

      expect(result.instructions, contains('- IPv4 address: 10.0.0.8'));
      expect(result.instructions, contains('- Broadcast address: 10.0.0.255'));
      expect(result.instructions, isNot(contains('Wi-Fi SSID')));
      expect(result.instructions, isNot(contains('IPv6 address')));
      expect(result.instructions, isNot(contains('Subnet mask')));
      expect(result.instructions, isNot(contains('Gateway IP')));
    });

    test('leaves context empty when no details are available', () async {
      final provider = NetworkContextProvider(
        source: _FakeNetworkInfoSource(
          wifiName: ' ',
          wifiIP: null,
          wifiIPv6Error: StateError('unsupported'),
          wifiSubmask: '',
          wifiGatewayIP: null,
          wifiBroadcast: '   ',
        ),
      );

      final result = await provider.invoking(_createInvokingContext());

      expect(result.instructions, isNull);
      expect(result.messages, isNull);
    });
  });

  group('get_current_network_info', () {
    test('returns structured network details with stable keys', () async {
      final tool = createCurrentNetworkInfoTool(
        source: _FakeNetworkInfoSource(
          wifiName: ' Studio Wi-Fi ',
          wifiBSSID: ' aa:bb:cc:dd:ee:ff ',
          wifiIP: ' 192.168.1.10 ',
          wifiIPv6: ' fe80::1 ',
          wifiSubmask: ' 255.255.255.0 ',
          wifiGatewayIP: ' 192.168.1.1 ',
          wifiBroadcast: ' 192.168.1.255 ',
        ),
      );

      final result = await tool.invoke(AIFunctionArguments());

      expect(tool.name, 'get_current_network_info');
      expect(result, {
        'ssid': 'Studio Wi-Fi',
        'bssid': 'aa:bb:cc:dd:ee:ff',
        'ipv4Address': '192.168.1.10',
        'ipv6Address': 'fe80::1',
        'subnetMask': '255.255.255.0',
        'gatewayIp': '192.168.1.1',
        'broadcastAddress': '192.168.1.255',
      });
    });

    test('omits unavailable fields and swallows platform errors', () async {
      final tool = createCurrentNetworkInfoTool(
        source: _FakeNetworkInfoSource(
          wifiName: null,
          wifiBSSID: '',
          wifiIP: '10.0.0.8',
          wifiIPv6Error: StateError('unsupported'),
          wifiSubmask: ' ',
          wifiGatewayIP: null,
          wifiBroadcast: '10.0.0.255',
        ),
      );

      final result = await tool.invoke(AIFunctionArguments());

      expect(result, {
        'ipv4Address': '10.0.0.8',
        'broadcastAddress': '10.0.0.255',
      });
    });

    test(
      'returns a helpful fallback when network info is unavailable',
      () async {
        final tool = createCurrentNetworkInfoTool(
          source: _FakeNetworkInfoSource(
            wifiNameError: StateError('unsupported'),
            wifiBSSID: null,
            wifiIP: '',
            wifiIPv6: ' ',
            wifiSubmask: null,
            wifiGatewayIP: '',
            wifiBroadcast: null,
          ),
        );

        expect(
          await tool.invoke(AIFunctionArguments()),
          'Network info is unavailable on this device or platform.',
        );
      },
    );
  });
}

InvokingContext _createInvokingContext() {
  return InvokingContext(_TestAgent(), null, null, AIContext());
}

final class _FakeNetworkInfoSource implements NetworkInfoSource {
  const _FakeNetworkInfoSource({
    this.wifiName,
    this.wifiBSSID,
    this.wifiIP,
    this.wifiIPv6,
    this.wifiSubmask,
    this.wifiGatewayIP,
    this.wifiBroadcast,
    this.wifiNameError,
    this.wifiIPv6Error,
  });

  final String? wifiName;
  final String? wifiBSSID;
  final String? wifiIP;
  final String? wifiIPv6;
  final String? wifiSubmask;
  final String? wifiGatewayIP;
  final String? wifiBroadcast;
  final Object? wifiNameError;
  final Object? wifiIPv6Error;

  @override
  Future<String?> getWifiName() => _value(wifiName, wifiNameError);

  @override
  Future<String?> getWifiBSSID() => _value(wifiBSSID, null);

  @override
  Future<String?> getWifiIP() => _value(wifiIP, null);

  @override
  Future<String?> getWifiIPv6() => _value(wifiIPv6, wifiIPv6Error);

  @override
  Future<String?> getWifiSubmask() => _value(wifiSubmask, null);

  @override
  Future<String?> getWifiGatewayIP() => _value(wifiGatewayIP, null);

  @override
  Future<String?> getWifiBroadcast() => _value(wifiBroadcast, null);

  Future<String?> _value(String? value, Object? error) async {
    if (error != null) throw error;
    return value;
  }
}

final class _TestAgent extends AIAgent {
  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? JsonSerializerOptions,
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
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }
}

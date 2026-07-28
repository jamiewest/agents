import 'dart:io';

Future<List<String>> resolveHost(String host) async => [
  for (final address in await InternetAddress.lookup(host)) address.address,
];

bool isPublicAddress(String address) {
  final parsed = InternetAddress.tryParse(address);
  if (parsed == null ||
      parsed.isLoopback ||
      parsed.isLinkLocal ||
      parsed.isMulticast) {
    return false;
  }

  final bytes = parsed.rawAddress;
  if (parsed.type == InternetAddressType.IPv4) {
    return !_isNonPublicIpv4(bytes);
  }

  if (_isIpv4MappedIpv6(bytes)) {
    return !_isNonPublicIpv4(bytes.sublist(12));
  }

  // Unspecified (::), unique-local (fc00::/7), documentation
  // (2001:db8::/32), and the deprecated site-local range (fec0::/10).
  final isUnspecified = bytes.every((byte) => byte == 0);
  final isUniqueLocal = (bytes[0] & 0xfe) == 0xfc;
  final isDocumentation =
      bytes[0] == 0x20 &&
      bytes[1] == 0x01 &&
      bytes[2] == 0x0d &&
      bytes[3] == 0xb8;
  final isSiteLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0xc0;
  return !isUnspecified && !isUniqueLocal && !isDocumentation && !isSiteLocal;
}

bool _isNonPublicIpv4(List<int> bytes) {
  final first = bytes[0];
  final second = bytes[1];

  return first == 0 ||
      first == 10 ||
      first == 127 ||
      (first == 100 && second >= 64 && second <= 127) ||
      (first == 169 && second == 254) ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 0 && bytes[2] == 0) ||
      (first == 192 && second == 0 && bytes[2] == 2) ||
      (first == 192 && second == 168) ||
      (first == 198 && (second == 18 || second == 19)) ||
      (first == 198 && second == 51 && bytes[2] == 100) ||
      (first == 203 && second == 0 && bytes[2] == 113) ||
      first >= 224;
}

bool _isIpv4MappedIpv6(List<int> bytes) =>
    bytes.length == 16 &&
    bytes.take(10).every((byte) => byte == 0) &&
    bytes[10] == 0xff &&
    bytes[11] == 0xff;

import 'dart:io';

import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final supported =
      !kIsWeb &&
      <TargetPlatform>{
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }.contains(defaultTargetPlatform);

  group('HeadlessWebViewPageLoader native', () {
    late HttpServer server;
    late Uri origin;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin = Uri.parse('http://127.0.0.1:${server.port}');
      server.listen(_serve);
    });

    tearDown(() => server.close(force: true));

    test('extracts JavaScript-rendered text and follows redirects', () async {
      final loader = _loader();

      final content = await loader.load(origin.resolve('/redirect'));

      expect(content.status, WebPageLoadStatus.success);
      expect(content.finalUrl?.path, '/dynamic');
      expect(content.title, 'Dynamic fixture');
      expect(content.text, contains('Rendered by JavaScript'));
    }, skip: !supported);

    test('revalidates and blocks redirect destinations', () async {
      final loader = _loader(blockedPaths: const <String>{'/private'});

      final content = await loader.load(origin.resolve('/redirect-blocked'));

      expect(content.status, WebPageLoadStatus.blocked);
      expect(content.finalUrl?.path, '/private');
    }, skip: !supported);

    test('returns timeout for a page that does not finish loading', () async {
      final loader = _loader(timeout: const Duration(milliseconds: 100));

      final content = await loader.load(origin.resolve('/slow'));

      expect(content.status, WebPageLoadStatus.timeout);
    }, skip: !supported);

    test('does not retain cookies between page loads', () async {
      final loader = _loader();

      final first = await loader.load(origin.resolve('/cookie'));
      final second = await loader.load(origin.resolve('/cookie'));

      expect(first.text, contains('fresh session'));
      expect(second.text, contains('fresh session'));
    }, skip: !supported);

    test('caps extracted text and marks it truncated', () async {
      final loader = _loader(maxPageCharacters: 20);

      final content = await loader.load(origin.resolve('/long'));

      expect(content.status, WebPageLoadStatus.success);
      expect(content.text, hasLength(20));
      expect(content.truncated, isTrue);
    }, skip: !supported);

    test('extracts structured blocks, outline, and JSON-LD', () async {
      final content = await _loader().load(origin.resolve('/structured'));

      expect(content.status, WebPageLoadStatus.success);
      expect(
        content.blocks.map((block) => block.type),
        containsAll(<WebContentBlockType>[
          WebContentBlockType.heading,
          WebContentBlockType.paragraph,
          WebContentBlockType.table,
        ]),
      );
      final table = content.blocks.singleWhere(
        (block) => block.type == WebContentBlockType.table,
      );
      expect(table.headingPath, contains('Fees'));
      expect(content.contentMarkdown, contains('### Fees'));
      expect(content.contentMarkdown, contains(r'| Electronic | $25 |'));
      expect(content.contentMarkdown, isNot(contains('Site navigation')));
      expect(content.outline.map((s) => s.heading), contains('Fees'));
      expect(content.structuredData.single.schemaType, 'Dataset');
      expect(content.boilerplateBlocks, greaterThan(0));
    }, skip: !supported);

    test('sends a custom browsing user agent when configured', () async {
      final loader = _loader(userAgent: 'AgentsBrowser/1.0');

      final content = await loader.load(origin.resolve('/user-agent'));

      expect(content.status, WebPageLoadStatus.success);
      expect(content.text, contains('AgentsBrowser/1.0'));
    }, skip: !supported);

    test('reports verification pages without interacting', () async {
      final content = await _loader().load(origin.resolve('/challenge'));

      expect(content.status, WebPageLoadStatus.challengeDetected);
      expect(content.message, contains('verification'));
    }, skip: !supported);

    test('stops a page load when cancellation is requested', () async {
      final source = CancellationTokenSource(const Duration(milliseconds: 50));
      addTearDown(source.dispose);

      await expectLater(
        _loader().load(
          origin.resolve('/slow'),
          cancellationToken: source.token,
        ),
        throwsA(isA<OperationCanceledException>()),
      );
    }, skip: !supported);
  });
}

HeadlessWebViewPageLoader _loader({
  Duration timeout = const Duration(seconds: 2),
  int maxPageCharacters = 20000,
  Set<String> blockedPaths = const <String>{},
  String? userAgent,
}) => HeadlessWebViewPageLoader(
  navigationPolicy: _FixturePolicy(blockedPaths),
  options: WebSearchToolOptions(
    pageLoadTimeout: timeout,
    domSettleDelay: const Duration(milliseconds: 50),
    maxPageCharacters: maxPageCharacters,
  ),
  userAgent: userAgent,
);

Future<void> _serve(HttpRequest request) async {
  switch (request.uri.path) {
    case '/redirect':
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(HttpHeaders.locationHeader, '/dynamic');
    case '/redirect-blocked':
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(HttpHeaders.locationHeader, '/private');
    case '/private':
      request.response
        ..headers.contentType = ContentType.html
        ..write('<main>Must not be returned</main>');
    case '/dynamic':
      request.response
        ..headers.contentType = ContentType.html
        ..write('''
<!doctype html>
<html>
  <head><title>Dynamic fixture</title></head>
  <body>
    <main id="content">Waiting</main>
    <script>
      document.getElementById('content').textContent =
        'Rendered by JavaScript';
    </script>
  </body>
</html>
''');
    case '/slow':
      await Future<void>.delayed(const Duration(seconds: 1));
      request.response
        ..headers.contentType = ContentType.html
        ..write('<main>Too late</main>');
    case '/cookie':
      final hasCookie = request.cookies.any(
        (cookie) => cookie.name == 'webview_test',
      );
      request.response
        ..headers.contentType = ContentType.html
        ..cookies.add(Cookie('webview_test', 'present'))
        ..write(
          hasCookie
              ? '<main>reused session</main>'
              : '<main>fresh session</main>',
        );
    case '/long':
      request.response
        ..headers.contentType = ContentType.html
        ..write('<main>${''.padLeft(100, 'x')}</main>');
    case '/structured':
      request.response
        ..headers.contentType = ContentType.html
        ..write(r'''
<!doctype html>
<html>
  <head>
    <title>Records fixture</title>
    <script type="application/ld+json">
      {"@type": "Dataset", "name": "Assessment roll"}
    </script>
  </head>
  <body>
    <nav><a href="/">Site navigation</a></nav>
    <main>
      <h1>Public Records</h1>
      <p>Request copies of county records.</p>
      <h2>Fees</h2>
      <table>
        <tr><th>Format</th><th>Fee</th></tr>
        <tr><td>Electronic</td><td>$25</td></tr>
      </table>
    </main>
  </body>
</html>
''');
    case '/user-agent':
      request.response
        ..headers.contentType = ContentType.html
        ..write(
          '<main>Agent: '
          '${request.headers.value(HttpHeaders.userAgentHeader) ?? 'none'}'
          '</main>',
        );
    case '/challenge':
      request.response
        ..headers.contentType = ContentType.html
        ..write('<main>Verify you are human</main>');
    default:
      request.response.statusCode = HttpStatus.notFound;
  }
  await request.response.close();
}

final class _FixturePolicy implements WebNavigationPolicy {
  const _FixturePolicy(this.blockedPaths);

  final Set<String> blockedPaths;

  @override
  Future<WebNavigationDecision> evaluate(Uri url) async =>
      blockedPaths.contains(url.path)
      ? const WebNavigationDecision.block('Fixture destination blocked.')
      : const WebNavigationDecision.allow();
}

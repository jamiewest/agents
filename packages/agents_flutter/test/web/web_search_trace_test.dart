// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/system.dart';
import 'package:flutter_test/flutter_test.dart';

WebSearchTraceEvent _event({String outcome = 'success'}) => WebSearchTraceEvent(
  tool: 'web_search',
  transport: 'http',
  requestUrl: Uri.parse('https://searx.example.com/search?q=test'),
  outcome: outcome,
  duration: const Duration(milliseconds: 12),
  capturedAt: DateTime(2026, 7, 29, 10, 30),
);

/// A page loader that replays one canned result or error.
class _FakePageLoader implements WebPageLoader {
  _FakePageLoader({this.content, this.error});

  final WebPageContent? content;
  final Object? error;
  Uri? seenUrl;

  @override
  Future<WebPageContent> load(
    Uri url, {
    CancellationToken? cancellationToken,
  }) async {
    seenUrl = url;
    if (error case final error?) throw error;
    return content!;
  }
}

void main() {
  test('drops events while disabled and records while enabled', () async {
    final log = WebSearchTraceLog();
    log.record(_event());
    expect(log.events, isEmpty);

    await log.setEnabled(true);
    log.record(_event());
    expect(log.events, hasLength(1));

    await log.setEnabled(false);
    log.record(_event());
    expect(log.events, hasLength(1), reason: 'kept but no longer recording');
  });

  test('lists newest first, caps the buffer, and clears', () async {
    final log = WebSearchTraceLog();
    await log.setEnabled(true);
    for (var i = 0; i < WebSearchTraceLog.maxEvents + 5; i++) {
      log.record(_event(outcome: 'event-$i'));
    }
    expect(log.events, hasLength(WebSearchTraceLog.maxEvents));
    expect(
      log.events.first.outcome,
      'event-${WebSearchTraceLog.maxEvents + 4}',
    );
    log.clear();
    expect(log.events, isEmpty);
  });

  test('persists the enabled flag through the key-value store', () async {
    final store = InMemoryKeyValueStore();
    final log = WebSearchTraceLog(keyValueStore: store);
    await log.load();
    expect(log.isEnabled, isFalse);

    await log.setEnabled(true);
    final restored = WebSearchTraceLog(keyValueStore: store);
    await restored.load();
    expect(restored.isEnabled, isTrue);

    await restored.setEnabled(false);
    final again = WebSearchTraceLog(keyValueStore: store);
    await again.load();
    expect(again.isEnabled, isFalse);
  });

  test('caps stored bodies at maxBodyCharacters', () {
    final capped = WebSearchTraceLog.cappedBody(
      'a' * (WebSearchTraceLog.maxBodyCharacters + 10),
    );
    expect(capped.length, WebSearchTraceLog.maxBodyCharacters);
    expect(WebSearchTraceLog.cappedBody('short'), 'short');
  });

  test('describe renders every captured detail', () {
    final text = WebSearchTraceEvent(
      tool: 'web_search',
      transport: 'http',
      query: 'flutter',
      requestUrl: Uri.parse('https://searx.example.com/search?q=flutter'),
      userAgent: 'Mozilla/5.0 (Test)',
      httpStatusCode: 200,
      outcome: 'success',
      resultCount: 3,
      responseBody: '{"results": []}',
      duration: const Duration(milliseconds: 42),
      capturedAt: DateTime(2026, 7, 29, 10, 30),
    ).describe();
    expect(text, contains('Query: flutter'));
    expect(
      text,
      contains('Request: GET https://searx.example.com/search?q=flutter'),
    );
    expect(text, contains('User-Agent: Mozilla/5.0 (Test)'));
    expect(text, contains('HTTP 200'));
    expect(text, contains('42 ms'));
    expect(text, contains('Results: 3'));
    expect(text, contains('{"results": []}'));
  });

  group('TracingWebPageLoader', () {
    test('records the load details around the inner result', () async {
      final log = WebSearchTraceLog();
      await log.setEnabled(true);
      final inner = _FakePageLoader(
        content: WebPageContent(
          status: WebPageLoadStatus.success,
          requestedUrl: Uri.parse('https://example.com/a'),
          finalUrl: Uri.parse('https://example.com/b'),
          title: 'Example',
          text: 'Readable page text.',
        ),
      );
      final loader = TracingWebPageLoader(inner, log);

      final content = await loader.load(Uri.parse('https://example.com/a'));

      expect(content.status, WebPageLoadStatus.success);
      expect(inner.seenUrl, Uri.parse('https://example.com/a'));
      final event = log.events.single;
      expect(event.tool, 'open_web_page');
      expect(event.transport, 'webview');
      expect(event.requestUrl, Uri.parse('https://example.com/a'));
      expect(event.finalUrl, Uri.parse('https://example.com/b'));
      expect(event.outcome, 'success');
      expect(event.responseBody, contains('Title: Example'));
      expect(event.responseBody, contains('Readable page text.'));
    });

    test('records HTTP error loads with their status code', () async {
      final log = WebSearchTraceLog();
      await log.setEnabled(true);
      final loader = TracingWebPageLoader(
        _FakePageLoader(
          content: WebPageContent(
            status: WebPageLoadStatus.httpError,
            requestedUrl: Uri.parse('https://example.com/missing'),
            httpStatusCode: 404,
            message: 'The page returned HTTP 404.',
          ),
        ),
        log,
      );

      await loader.load(Uri.parse('https://example.com/missing'));

      final event = log.events.single;
      expect(event.outcome, 'httpError');
      expect(event.httpStatusCode, 404);
      expect(event.responseBody, contains('The page returned HTTP 404.'));
    });

    test('records a thrown load as an error event and rethrows', () async {
      final log = WebSearchTraceLog();
      await log.setEnabled(true);
      final loader = TracingWebPageLoader(
        _FakePageLoader(error: StateError('boom')),
        log,
      );

      await expectLater(
        loader.load(Uri.parse('https://example.com')),
        throwsStateError,
      );
      final event = log.events.single;
      expect(event.outcome, 'error');
      expect(event.error, contains('boom'));
    });

    test('records the browsing user agent when one is configured', () async {
      final log = WebSearchTraceLog();
      await log.setEnabled(true);
      final loader = TracingWebPageLoader(
        _FakePageLoader(
          content: WebPageContent(
            status: WebPageLoadStatus.success,
            requestedUrl: Uri.parse('https://example.com'),
            text: 'text',
          ),
        ),
        log,
        userAgent: 'AgentsBrowser/1.0',
      );

      await loader.load(Uri.parse('https://example.com'));

      expect(log.events.single.userAgent, 'AgentsBrowser/1.0');
    });

    test('stays silent while tracing is off', () async {
      final log = WebSearchTraceLog();
      final loader = TracingWebPageLoader(
        _FakePageLoader(
          content: WebPageContent(
            status: WebPageLoadStatus.success,
            requestedUrl: Uri.parse('https://example.com'),
            text: 'text',
          ),
        ),
        log,
      );

      final content = await loader.load(Uri.parse('https://example.com'));

      expect(content.text, 'text');
      expect(log.events, isEmpty);
    });
  });
}

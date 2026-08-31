import 'package:extensions/ai.dart';
import 'package:test/test.dart';

import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/shared/usage_aggregation_extensions.dart';
import 'package:agents/src/shared/usage_aggregator.dart';

void main() {
  group('UsageAggregator.combine', () {
    test('returns null when both sides are null', () {
      expect(UsageAggregator.combine(null, null), isNull);
    });

    test('returns a copy when only one side is present', () {
      final incoming = UsageDetails(inputTokenCount: 3, outputTokenCount: 5);

      final combined = UsageAggregator.combine(null, incoming)!;

      expect(combined.inputTokenCount, 3);
      expect(combined.outputTokenCount, 5);
      expect(identical(combined, incoming), isFalse);
    });

    test('sums every strongly-typed counter', () {
      final current = UsageDetails(
        inputTokenCount: 1,
        outputTokenCount: 2,
        totalTokenCount: 3,
        cachedInputTokenCount: 4,
        reasoningTokenCount: 5,
      );
      final incoming = UsageDetails(
        inputTokenCount: 10,
        outputTokenCount: 20,
        totalTokenCount: 30,
        cachedInputTokenCount: 40,
        reasoningTokenCount: 50,
      );

      final combined = UsageAggregator.combine(current, incoming)!;

      expect(combined.inputTokenCount, 11);
      expect(combined.outputTokenCount, 22);
      expect(combined.totalTokenCount, 33);
      expect(combined.cachedInputTokenCount, 44);
      expect(combined.reasoningTokenCount, 55);
    });

    test('treats null counts as not reported rather than zero', () {
      final current = UsageDetails(inputTokenCount: 1);
      final incoming = UsageDetails(outputTokenCount: 2);

      final combined = UsageAggregator.combine(current, incoming)!;

      expect(combined.inputTokenCount, 1);
      expect(combined.outputTokenCount, 2);
      expect(combined.totalTokenCount, isNull);
    });

    test('sums additional counts per key', () {
      final current = UsageDetails(additionalCounts: {'cache': 2, 'cost': 1});
      final incoming = UsageDetails(additionalCounts: {'cache': 3, 'new': 7});

      final combined = UsageAggregator.combine(current, incoming)!;

      expect(combined.additionalCounts, {'cache': 5, 'cost': 1, 'new': 7});
    });

    test('mutates neither argument', () {
      final current = UsageDetails(
        inputTokenCount: 1,
        additionalCounts: {'cache': 2},
      );
      final incoming = UsageDetails(
        inputTokenCount: 2,
        additionalCounts: {'cache': 3},
      );

      final combined = UsageAggregator.combine(current, incoming)!;

      expect(current.inputTokenCount, 1);
      expect(current.additionalCounts, {'cache': 2});
      expect(incoming.inputTokenCount, 2);
      expect(incoming.additionalCounts, {'cache': 3});
      expect(identical(combined, current), isFalse);
      expect(identical(combined, incoming), isFalse);
    });
  });

  group('applyAggregatedUsage', () {
    test('replaces the usage on the same agent response instance', () {
      final response = AgentResponse(
        message: ChatMessage.fromText(ChatRole.assistant, 'hi'),
      )..usage = UsageDetails(inputTokenCount: 1);
      final aggregated = UsageDetails(inputTokenCount: 9);

      final result = response.applyAggregatedUsage(aggregated);

      expect(identical(result, response), isTrue);
      expect(response.usage, same(aggregated));
    });

    test('replaces the messages when a transcript is supplied', () {
      final response = AgentResponse(
        message: ChatMessage.fromText(ChatRole.assistant, 'last'),
      );
      final transcript = [
        ChatMessage.fromText(ChatRole.assistant, 'first'),
        ChatMessage.fromText(ChatRole.assistant, 'last'),
      ];

      response.applyAggregatedUsage(null, messages: transcript);

      expect(response.messages, hasLength(2));
      expect(response.usage, isNull);
    });

    test('replaces the usage on the same chat response instance', () {
      final response = ChatResponse.fromMessage(
        ChatMessage.fromText(ChatRole.assistant, 'hi'),
      )..usage = UsageDetails(inputTokenCount: 1);
      final aggregated = UsageDetails(inputTokenCount: 9);

      final result = response.applyAggregatedUsage(aggregated);

      expect(identical(result, response), isTrue);
      expect(response.usage, same(aggregated));
    });
  });
}

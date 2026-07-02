// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectChatFormatName', () {
    const cases = <String, String?>{
      // Groq-style model ids.
      'llama-3.3-70b-versatile': 'llama3',
      'llama-3.1-8b-instant': 'llama3',
      'meta-llama/llama-4-scout': null,
      'qwen/qwen3-32b': 'qwen',
      'qwen-2.5-coder-32b': 'qwen',
      'deepseek-r1-distill-llama-70b': 'chatml',
      'mixtral-8x7b-32768': 'mistral',
      'gemma2-9b-it': 'gemma',
      'gpt-4o': null,
      // GGUF file names.
      'Qwen2.5-7B-Instruct-Q4_K_M.gguf': 'qwen',
      'QwQ-32B-Q4_K_M.gguf': 'qwen',
      'Meta-Llama-3-8B-Instruct.Q5_K_M.gguf': 'llama3',
      'Mistral-7B-Instruct-v0.3.Q4_K_M.gguf': 'mistral',
      'Ministral-8B-Instruct-Q4.gguf': 'mistral',
      'gemma-3-4b-it-Q4_K_M.gguf': 'gemma',
      'LFM2-1.2B-Q4_K_M.gguf': 'lfm2',
      'LFM2.5-3B-Q4_0.gguf': 'lfm2.5',
      'lfm25-vl-3b.gguf': 'lfm2.5',
      'Hermes-2-Pro-Mistral-7B.Q4.gguf': 'chatml',
      'SmolLM2-1.7B-Instruct.gguf': 'chatml',
      'TinyLlama-1.1B-Chat.gguf': 'chatml',
      'Phi-3-mini-4k-instruct.gguf': 'chatml',
      'totally-unknown-model.bin': null,
    };

    cases.forEach((name, expected) {
      test('$name -> $expected', () {
        expect(detectChatFormatName(name), expected);
      });
    });
  });

  group('detectModelProfile', () {
    test('flags think tags for reasoning models', () {
      expect(detectModelProfile('qwen/qwen3-32b').thinkTags, isTrue);
      expect(detectModelProfile('QwQ-32B.gguf').thinkTags, isTrue);
      expect(
        detectModelProfile('deepseek-r1-distill-llama-70b').thinkTags,
        isTrue,
      );
    });

    test('does not flag think tags for plain instruct models', () {
      expect(detectModelProfile('llama-3.3-70b-versatile').thinkTags, isFalse);
      expect(detectModelProfile('qwen-2.5-coder').thinkTags, isFalse);
      expect(detectModelProfile('gemma2-9b-it').thinkTags, isFalse);
    });

    test('unknown models detect nothing', () {
      final detection = detectModelProfile('gpt-4o-mini');
      expect(detection.formatName, isNull);
      expect(detection.thinkTags, isFalse);
    });
  });

  group('OpenAIModelProfile.resolve', () {
    test('defaults to native tools with parallel calls', () {
      final profile = OpenAIModelProfile.resolve(
        modelId: 'llama-3.3-70b-versatile',
      );
      expect(profile.toolMode, ToolCallingMode.native);
      expect(profile.parallelToolCalls, isTrue);
      expect(profile.reasoningTags, ReasoningTagStyle.none);
      expect(profile.fallbackFormatName, 'llama3');
    });

    test('detection fills reasoning tags for qwen3', () {
      final profile = OpenAIModelProfile.resolve(modelId: 'qwen/qwen3-32b');
      expect(profile.reasoningTags, ReasoningTagStyle.thinkTags);
      expect(profile.fallbackFormatName, 'qwen');
    });

    test('explicit settings override detection', () {
      final profile = OpenAIModelProfile.resolve(
        modelId: 'qwen/qwen3-32b',
        settings: const {
          toolsModeSetting: toolsModePrompt,
          toolsParallelSetting: 'false',
          reasoningTagsSetting: reasoningTagsNone,
          chatFormatSetting: 'mistral',
        },
      );
      expect(profile.toolMode, ToolCallingMode.promptInjected);
      expect(profile.parallelToolCalls, isFalse);
      expect(profile.reasoningTags, ReasoningTagStyle.none);
      expect(profile.fallbackFormatName, 'mistral');
    });

    test('empty settings values fall back to detection', () {
      final profile = OpenAIModelProfile.resolve(
        modelId: 'qwen/qwen3-32b',
        settings: const {chatFormatSetting: '', reasoningTagsSetting: ''},
      );
      expect(profile.fallbackFormatName, 'qwen');
      expect(profile.reasoningTags, ReasoningTagStyle.thinkTags);
    });
  });

  group('resolveToolFormat', () {
    test('maps registry names to formats', () {
      expect(resolveToolFormat('qwen'), isA<HermesToolFormat>());
      expect(resolveToolFormat('chatml'), isA<HermesToolFormat>());
      expect(resolveToolFormat('gemma'), isA<HermesToolFormat>());
      expect(resolveToolFormat('llama3'), isA<Llama3ToolFormat>());
      expect(resolveToolFormat('mistral'), isA<MistralToolFormat>());
      expect(resolveToolFormat('lfm2'), isA<Lfm2ToolFormat>());
      final lfm25 = resolveToolFormat('lfm2.5');
      expect(lfm25, isA<Lfm2ToolFormat>());
      expect((lfm25! as Lfm2ToolFormat).style, LfmToolTagStyle.lfm25);
    });

    test('defaults to Hermes for null or empty', () {
      expect(resolveToolFormat(null), isA<HermesToolFormat>());
      expect(resolveToolFormat(''), isA<HermesToolFormat>());
    });

    test('returns null for unknown names', () {
      expect(resolveToolFormat('betamax'), isNull);
    });
  });
}

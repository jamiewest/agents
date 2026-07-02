// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelCapabilities', () {
    test('defaults are conservative when settings are absent', () {
      final capabilities = ModelCapabilities.fromSettings(const {});

      expect(capabilities.supportsThinking, isFalse);
      expect(capabilities.supportsVision, isFalse);
      expect(capabilities.supportsTools, isTrue);
      expect(capabilities.contextLength, isNull);
      expect(capabilities.minMemoryMb, isNull);
    });

    test('round-trips through settings entries', () {
      const capabilities = ModelCapabilities(
        supportsThinking: true,
        supportsVision: true,
        supportsTools: false,
        contextLength: 128000,
        minMemoryMb: 8192,
      );

      final restored = ModelCapabilities.fromSettings(
        capabilities.toSettings(),
      );

      expect(restored.supportsThinking, isTrue);
      expect(restored.supportsVision, isTrue);
      expect(restored.supportsTools, isFalse);
      expect(restored.contextLength, 128000);
      expect(restored.minMemoryMb, 8192);
    });

    test('toSettings omits defaults so stored models stay untouched', () {
      expect(const ModelCapabilities().toSettings(), isEmpty);
    });

    test('reads through the ModelConfig extension', () {
      const model = ModelConfig(
        id: 'm1',
        sourceId: 's1',
        modelId: 'claude-x',
        settings: {'capability.thinking': 'true'},
      );

      expect(model.capabilities.supportsThinking, isTrue);
      expect(model.capabilities.supportsTools, isTrue);
    });
  });
}

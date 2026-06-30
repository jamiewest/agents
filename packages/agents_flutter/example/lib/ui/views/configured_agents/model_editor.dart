// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter/material.dart';

import '../../strings/configured_agents_strings.dart';
import '../../styles/configured_agents_style.dart';
import 'configured_agents_form_field.dart';
import 'editor_actions.dart';

/// Editor form for creating or updating a [ModelConfig].
class ModelEditor extends StatefulWidget {
  /// Creates a [ModelEditor].
  const ModelEditor({
    required this.sources,
    required this.style,
    required this.strings,
    required this.onSubmit,
    required this.onCancel,
    this.initial,
    super.key,
  });

  /// The model being edited, or `null` to create a new one.
  final ModelConfig? initial;

  /// Sources the model may belong to. Must be non-empty.
  final List<ModelSourceConfig> sources;

  /// Resolved style.
  final ConfiguredAgentsStyle style;

  /// Resolved strings.
  final ConfiguredAgentsStrings strings;

  /// Called with the edited model.
  final void Function(ModelConfig model) onSubmit;

  /// Called when the user cancels.
  final VoidCallback onCancel;

  @override
  State<ModelEditor> createState() => _ModelEditorState();
}

class _ModelEditorState extends State<ModelEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _modelId;
  late final TextEditingController _displayName;
  late final TextEditingController _llamaModelUrl;
  late final TextEditingController _llamaContextSize;
  late final TextEditingController _llamaGpuLayers;
  late final TextEditingController _llamaFormat;
  late String _sourceId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _modelId = TextEditingController(text: initial?.modelId ?? '');
    _displayName = TextEditingController(text: initial?.displayName ?? '');
    _llamaModelUrl = TextEditingController(
      text: initial?.settings['llama.modelUrl'] ?? '',
    );
    _llamaContextSize = TextEditingController(
      text: initial?.settings['llama.contextSize'] ?? '4096',
    );
    _llamaGpuLayers = TextEditingController(
      text: initial?.settings['llama.gpuLayers'] ?? '999',
    );
    _llamaFormat = TextEditingController(
      text: initial?.settings['llama.format'] ?? 'gemma',
    );
    _sourceId = initial?.sourceId ?? widget.sources.first.id;
  }

  @override
  void dispose() {
    _modelId.dispose();
    _displayName.dispose();
    _llamaModelUrl.dispose();
    _llamaContextSize.dispose();
    _llamaGpuLayers.dispose();
    _llamaFormat.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final displayName = _displayName.text.trim();
    final isLocal = _selectedSource.providerType == ProviderType.localLlama;
    final id = widget.initial?.id ?? newConfiguredAgentsId();
    final settings = isLocal
        ? <String, String>{
            'llama.modelUrl': _llamaModelUrl.text.trim(),
            'llama.contextSize': _llamaContextSize.text.trim(),
            'llama.gpuLayers': _llamaGpuLayers.text.trim(),
            'llama.format': _llamaFormat.text.trim().isEmpty
                ? 'gemma'
                : _llamaFormat.text.trim(),
          }
        : widget.initial?.settings ?? const <String, String>{};
    widget.onSubmit(
      ModelConfig(
        id: id,
        sourceId: _sourceId,
        modelId: isLocal ? widget.initial?.modelId ?? id : _modelId.text.trim(),
        displayName: displayName.isEmpty ? null : displayName,
        settings: settings,
      ),
    );
  }

  ModelSourceConfig get _selectedSource => widget.sources.firstWhere(
    (source) => source.id == _sourceId,
    orElse: () => widget.sources.first,
  );

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final style = widget.style;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.sourceLabel, style: style.labelTextStyle),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _sourceId,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    for (final source in widget.sources)
                      DropdownMenuItem(
                        value: source.id,
                        child: Text(source.displayName),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _sourceId = value ?? _sourceId);
                  },
                ),
              ],
            ),
          ),
          if (_selectedSource.providerType == ProviderType.localLlama) ...[
            ConfiguredAgentsFormField(
              label: 'GGUF model URL',
              controller: _llamaModelUrl,
              style: style,
              keyboardType: TextInputType.url,
              hintText:
                  'https://huggingface.co/org/repo/resolve/main/model-00001-of-00002.gguf',
              validator: (value) {
                final text = value?.trim() ?? '';
                final uri = Uri.tryParse(text);
                return text.isEmpty || uri == null || !uri.isAbsolute
                    ? strings.invalidEndpoint
                    : null;
              },
            ),
            ConfiguredAgentsFormField(
              label: 'Context size',
              controller: _llamaContextSize,
              style: style,
              keyboardType: TextInputType.number,
              validator: (value) => int.tryParse(value?.trim() ?? '') == null
                  ? strings.invalidNumber
                  : null,
            ),
            ConfiguredAgentsFormField(
              label: 'GPU layers',
              controller: _llamaGpuLayers,
              style: style,
              keyboardType: TextInputType.number,
              validator: (value) => int.tryParse(value?.trim() ?? '') == null
                  ? strings.invalidNumber
                  : null,
            ),
            ConfiguredAgentsFormField(
              label: 'Format',
              controller: _llamaFormat,
              style: style,
              hintText: 'gemma',
              validator: (value) {
                final text = (value ?? '').trim();
                return text.isEmpty || text == 'gemma'
                    ? null
                    : 'Only gemma is supported.';
              },
            ),
          ] else
            ConfiguredAgentsFormField(
              label: strings.modelIdLabel,
              controller: _modelId,
              style: style,
              hintText: 'gpt-4o',
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? strings.requiredField
                  : null,
            ),
          ConfiguredAgentsFormField(
            label: strings.modelDisplayNameLabel,
            controller: _displayName,
            style: style,
          ),
          const SizedBox(height: 12),
          EditorActions(
            style: style,
            strings: strings,
            onCancel: widget.onCancel,
            onSave: _submit,
          ),
        ],
      ),
    );
  }
}

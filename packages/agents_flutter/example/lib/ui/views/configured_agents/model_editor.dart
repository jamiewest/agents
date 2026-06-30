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
  late String _sourceId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _modelId = TextEditingController(text: initial?.modelId ?? '');
    _displayName = TextEditingController(text: initial?.displayName ?? '');
    _sourceId = initial?.sourceId ?? widget.sources.first.id;
  }

  @override
  void dispose() {
    _modelId.dispose();
    _displayName.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final displayName = _displayName.text.trim();
    widget.onSubmit(
      ModelConfig(
        id: widget.initial?.id ?? newConfiguredAgentsId(),
        sourceId: _sourceId,
        modelId: _modelId.text.trim(),
        displayName: displayName.isEmpty ? null : displayName,
      ),
    );
  }

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
                  onChanged: (value) =>
                      setState(() => _sourceId = value ?? _sourceId),
                ),
              ],
            ),
          ),
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

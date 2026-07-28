// Minimal `agents_flutter` example.
//
// Builds a `FlutterHarnessAgent` from an Anthropic-backed `ChatClient` and
// runs a single turn against it. The harness supplies compaction, function
// invocation, and the Flutter device-capability context providers and tools,
// so the agent can answer questions such as "what time is it?" or "am I
// online?" without any extra wiring.
//
// Run with:
//   flutter run --dart-define=ANTHROPIC_API_KEY=sk-ant-...

import 'package:agents/agents.dart';
import 'package:agents_flutter/agents_flutter.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;
import 'package:flutter/material.dart';

const _apiKey = String.fromEnvironment('ANTHROPIC_API_KEY');

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'agents_flutter example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const AgentPage(),
    );
  }
}

class AgentPage extends StatefulWidget {
  const AgentPage({super.key});

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  final TextEditingController _controller = TextEditingController(
    text: 'What is today\'s date, and am I online?',
  );

  late final AIAgent _agent = _createAgent();
  AgentSession? _session;

  String _answer = '';
  bool _busy = false;

  /// Wraps an Anthropic chat client in the Flutter harness.
  ///
  /// The two positional arguments are the model's context-window size and its
  /// per-response output limit; both configure compaction. Safe-core
  /// capabilities (temporal, connectivity, app info, device info) are on by
  /// default — location, detailed network info, and the wake-lock tool are
  /// opt-in.
  AIAgent _createAgent() {
    final chatClient = anthropic.AnthropicClient(
      config: anthropic.AnthropicConfig(
        authProvider: anthropic.ApiKeyProvider(_apiKey),
      ),
    ).asChatClient(modelId: 'claude-opus-5');

    return chatClient.asFlutterHarnessAgent(
      1000000, // model context-window tokens
      128000, // model per-response output tokens
      options: FlutterHarnessAgentOptions()..enableWakeLock = true,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _answer = '';
    });

    try {
      final session = _session ??= await _agent.createSession();
      final response = await _agent.run(
        session,
        null,
        message: _controller.text,
      );
      if (mounted) {
        setState(() => _answer = response.text);
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _answer = 'Failed: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('agents_flutter')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Ask the agent',
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: Text(_busy ? 'Running…' : 'Send'),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(child: SelectableText(_answer)),
            ),
          ],
        ),
      ),
    );
  }
}

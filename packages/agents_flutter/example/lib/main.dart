import 'package:agents/agents.dart';
import 'package:agents_flutter/agents_flutter.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;
import 'package:extensions/extensions.dart';
import 'package:extensions_flutter/extensions_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _anthropicApiKey = String.fromEnvironment('ANTHROPIC_API_KEY');
const _anthropicModel = String.fromEnvironment(
  'ANTHROPIC_MODEL',
  defaultValue: 'claude-haiku-4-5-20251001',
);
const _anthropicMaxTokensValue = String.fromEnvironment(
  'ANTHROPIC_MAX_TOKENS',
  defaultValue: '4096',
);
const _defaultAnthropicMaxTokens = 4096;
const _anthropicWebHeaders = <String, String>{
  'anthropic-dangerous-direct-browser-access': 'true',
};

final _builder = Host.createApplicationBuilder()
  ..services.addFlutter((flutter) {
    if (_hasAnthropicApiKey) {
      final anthropicClient = anthropic.AnthropicClient.withApiKey(
        _anthropicApiKey,
        defaultHeaders: kIsWeb ? _anthropicWebHeaders : null,
      );
      final chatClient = anthropicClient.asChatClient(
        modelId: _anthropicModel,
        defaultMaxTokens: _anthropicMaxTokens,
      );

      flutter.useFlutterHarnessAgent(
        maxOutputTokens: _anthropicMaxTokens,
        chatClient: chatClient,
      );
    }

    flutter.runApp(
      (services) => AgentsFlutterExampleApp(
        agent: _hasAnthropicApiKey
            ? services.getRequiredService<AIAgent>()
            : null,
      ),
    );
  });

final host = _builder.build();

Future<void> main() async => host.run();

bool get _hasAnthropicApiKey => _anthropicApiKey.trim().isNotEmpty;

int get _anthropicMaxTokens {
  final value = int.tryParse(_anthropicMaxTokensValue);
  if (value == null || value <= 0) return _defaultAnthropicMaxTokens;
  return value;
}

class AgentsFlutterExampleApp extends StatelessWidget {
  const AgentsFlutterExampleApp({this.agent, super.key});

  final AIAgent? agent;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'agents_flutter example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        textTheme: GoogleFonts.outfitTextTheme(),
        useMaterial3: true,
      ),
      home: agent == null
          ? const MissingApiKeyScreen()
          : ChatDemoScreen(agent: agent!),
    );
  }
}

class MissingApiKeyScreen extends StatelessWidget {
  const MissingApiKeyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('agents_flutter chat UI')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Anthropic API key required', style: textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(
                  'Run the example with an Anthropic key supplied as a '
                  'compile-time define:',
                  style: textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                SelectableText(
                  'flutter run --dart-define=ANTHROPIC_API_KEY=sk-ant-...',
                  style: textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'For Flutter web, keep this local-demo only: browser builds '
                  'expose client-side API keys. Production apps should proxy '
                  'Anthropic requests through a backend.',
                  style: textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChatDemoScreen extends StatefulWidget {
  const ChatDemoScreen({required this.agent, super.key});

  final AIAgent agent;

  @override
  State<ChatDemoScreen> createState() => _ChatDemoScreenState();
}

class _ChatDemoScreenState extends State<ChatDemoScreen> {
  late final Future<AgentLlmProvider> _providerFuture;
  AgentLlmProvider? _provider;

  @override
  void initState() {
    super.initState();
    _providerFuture = _createProvider();
  }

  Future<AgentLlmProvider> _createProvider() async {
    final session = await widget.agent.createSession();
    final provider = AgentLlmProvider(agent: widget.agent, session: session);
    _provider = provider;
    return provider;
  }

  @override
  void dispose() {
    _provider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AgentLlmProvider>(
      future: _providerFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _SessionErrorScreen(error: snapshot.error!);
        }

        final provider = snapshot.data;
        if (provider == null) {
          return const _SessionLoadingScreen();
        }

        return _ChatScreen(provider: provider);
      },
    );
  }
}

class _SessionLoadingScreen extends StatelessWidget {
  const _SessionLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: _ChatAppBar(),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _SessionErrorScreen extends StatelessWidget {
  const _SessionErrorScreen({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: const _ChatAppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not start the agent session.\n\n$error',
            style: textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _ChatScreen extends StatelessWidget {
  const _ChatScreen({required this.provider});

  final AgentLlmProvider provider;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _ChatAppBar(onClear: () => provider.history = const []),
      body: LlmChatView(
        provider: provider,
        style: _demoStyle(),
        welcomeMessage: 'Ask Claude anything.',
        suggestions: const [
          'Show me a markdown response',
          'What Flutter device context can you see?',
          'Stream a short checklist',
        ],
        enableAttachments: false,
        enableVoiceNotes: false,
      ),
    );
  }
}

class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ChatAppBar({this.onClear});

  final VoidCallback? onClear;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('agents_flutter chat UI'),
      actions: [
        if (onClear != null)
          IconButton(
            tooltip: 'Clear chat',
            icon: const Icon(Icons.delete_outline),
            onPressed: onClear,
          ),
      ],
    );
  }
}

LlmChatViewStyle _demoStyle() {
  const submitStyle = ActionButtonStyle(icon: Icons.arrow_upward);
  return const LlmChatViewStyle(
    addButtonStyle: ActionButtonStyle(icon: Icons.add),
    attachFileButtonStyle: ActionButtonStyle(icon: Icons.attach_file),
    cameraButtonStyle: ActionButtonStyle(icon: Icons.photo_camera_outlined),
    stopButtonStyle: ActionButtonStyle(icon: Icons.stop),
    closeButtonStyle: ActionButtonStyle(icon: Icons.close),
    cancelButtonStyle: ActionButtonStyle(icon: Icons.close),
    copyButtonStyle: ActionButtonStyle(icon: Icons.copy),
    editButtonStyle: ActionButtonStyle(icon: Icons.edit),
    galleryButtonStyle: ActionButtonStyle(icon: Icons.photo_outlined),
    recordButtonStyle: ActionButtonStyle(icon: Icons.mic),
    submitButtonStyle: submitStyle,
    disabledButtonStyle: submitStyle,
    closeMenuButtonStyle: ActionButtonStyle(icon: Icons.close),
    urlButtonStyle: ActionButtonStyle(icon: Icons.link),
    llmMessageStyle: LlmMessageStyle(icon: Icons.auto_awesome),
    fileAttachmentStyle: FileAttachmentStyle(icon: Icons.insert_drive_file),
  );
}

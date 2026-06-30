import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions_flutter/extensions_flutter.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:extensions/extensions.dart';

import 'ui/providers/providers.dart';
import 'ui/views/configured_agents/configured_agents.dart';
import 'ui/views/llm_chat_view/llm_chat_view.dart';

// Optional seed values so the demo can start with a working Anthropic agent.
// Supply them as compile-time defines, e.g.
//   flutter run --dart-define=ANTHROPIC_API_KEY=sk-ant-...
// They are only used to pre-populate the runtime configuration on first launch;
// thereafter sources, models, and agents are managed entirely in the UI.
const _seedApiKey = String.fromEnvironment('ANTHROPIC_API_KEY');
const _seedModel = String.fromEnvironment(
  'ANTHROPIC_MODEL',
  defaultValue: 'claude-haiku-4-5-20251001',
);

// This is how we build and run the application, dont stray.
// <start>
final _builder = Host.createApplicationBuilder()
  ..logging.setMinimumLevel(LogLevel.trace)
  ..services.addFlutter((flutter) {
    flutter.useFlutterHarnessAgent();
    flutter.useConfiguredAgents();
    flutter.runApp((services) => const AgentsFlutterExampleApp());
  });

final host = _builder.build();

Future<void> main() async => await host.run();
// </start>

/// Root of the configured-agents example app.
class AgentsFlutterExampleApp extends StatelessWidget {
  /// Creates the example app.
  const AgentsFlutterExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'agents_flutter example',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      textTheme: GoogleFonts.outfitTextTheme(),
      useMaterial3: true,
    ),
    home: const HomeScreen(),
  );
}

/// Lists configured agents and opens the settings surface and chat.
class HomeScreen extends StatefulWidget {
  /// Creates a [HomeScreen].
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Future<void> _ready;
  bool _initialized = false;

  // Bumped whenever the saved agents may have changed (e.g. after returning
  // from settings) to force [_AgentList] to rebuild from storage.
  int _agentListToken = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _ready = _seedIfNeeded(
      context.getRequiredService<ConfiguredAgentsManager>(),
    );
  }

  Future<void> _seedIfNeeded(ConfiguredAgentsManager manager) async {
    if (_seedApiKey.trim().isEmpty) return;
    final existing = await manager.sources.listSources();
    if (existing.isNotEmpty) return;

    const sourceId = 'seed-anthropic';
    const modelId = 'seed-anthropic-model';
    await manager.saveSource(
      const ModelSourceConfig(
        id: sourceId,
        providerType: ProviderType.anthropic,
        displayName: 'Anthropic (seeded)',
      ),
      apiKey: _seedApiKey,
    );
    await manager.saveModel(
      const ModelConfig(
        id: modelId,
        sourceId: sourceId,
        modelId: _seedModel,
        displayName: 'Claude',
      ),
    );
    await manager.saveAgent(
      const SavedAgentConfig(
        id: 'seed-anthropic-agent',
        name: 'Claude',
        modelId: modelId,
        description: 'A helpful assistant.',
        instructions: 'You are a helpful, concise assistant.',
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    if (mounted) {
      setState(() => _agentListToken++);
    }
  }

  void _openChat(SavedAgentConfig agent) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ChatScreen(agent: agent)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Configured agents'),
      actions: [
        IconButton(
          tooltip: 'Manage',
          icon: const Icon(Icons.settings_outlined),
          onPressed: _openSettings,
        ),
      ],
    ),
    body: FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return _AgentList(
          key: ValueKey(_agentListToken),
          onSelected: _openChat,
          onManage: _openSettings,
        );
      },
    ),
  );
}

class _AgentList extends StatefulWidget {
  const _AgentList({
    required this.onSelected,
    required this.onManage,
    super.key,
  });

  final void Function(SavedAgentConfig agent) onSelected;
  final VoidCallback onManage;

  @override
  State<_AgentList> createState() => _AgentListState();
}

class _AgentListState extends State<_AgentList> {
  late final Future<List<SavedAgentConfig>> _agents;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _agents = context
        .getRequiredService<ConfiguredAgentsManager>()
        .agents
        .listAgents();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SavedAgentConfig>>(
    future: _agents,
    builder: (context, snapshot) {
      final agents = snapshot.data ?? const <SavedAgentConfig>[];
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (agents.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No agents yet. Add a source, model, and agent to begin.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: widget.onManage,
                  icon: const Icon(Icons.add),
                  label: const Text('Manage agents'),
                ),
              ],
            ),
          ),
        );
      }
      return ConfiguredAgentPicker(
        agents: agents,
        onSelected: widget.onSelected,
      );
    },
  );
}

/// The settings surface, composed entirely from the package's
/// [ConfiguredAgentsView].
class SettingsScreen extends StatelessWidget {
  /// Creates a [SettingsScreen].
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = context.getRequiredService<ConfiguredAgentsManager>();
    return Scaffold(
      appBar: AppBar(title: const Text('Manage agents')),
      body: Column(
        children: [
          const _WebSecurityNotice(),
          Expanded(child: ConfiguredAgentsView(manager: manager)),
        ],
      ),
    );
  }
}

class _WebSecurityNotice extends StatelessWidget {
  const _WebSecurityNotice();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    padding: const EdgeInsets.all(12),
    child: Text(
      'Keys are stored in secure storage. On the web this falls back to '
      'browser storage, which does not protect secrets — production apps '
      'should proxy provider requests through a backend.',
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

/// Resolves a saved agent and shows a chat against it.
class ChatScreen extends StatefulWidget {
  /// Creates a [ChatScreen].
  const ChatScreen({required this.agent, super.key});

  /// The saved agent to chat with.
  final SavedAgentConfig agent;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final Future<AgentLlmProvider> _providerFuture;
  bool _initialized = false;
  AgentLlmProvider? _provider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _providerFuture = _createProvider(
      context.getRequiredService<ConfiguredAgentFactory>(),
    );
  }

  Future<AgentLlmProvider> _createProvider(
    ConfiguredAgentFactory factory,
  ) async {
    final agent = await factory.createAgent(widget.agent);
    final session = await agent.createSession();
    final provider = AgentLlmProvider(agent: agent, session: session);
    _provider = provider;
    return provider;
  }

  @override
  void dispose() {
    _provider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.agent.name)),
    body: FutureBuilder<AgentLlmProvider>(
      future: _providerFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not start the agent.\n\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final provider = snapshot.data;
        if (provider == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return LlmChatView(
          provider: provider,
          welcomeMessage: 'Ask ${widget.agent.name} anything.',
          enableAttachments: false,
          enableVoiceNotes: false,
        );
      },
    ),
  );
}

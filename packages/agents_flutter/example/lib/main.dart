import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

void main() => runApp(const AgentsFlutterExampleApp());

/// Root of the configured-agents example app.
class AgentsFlutterExampleApp extends StatefulWidget {
  /// Creates the example app.
  const AgentsFlutterExampleApp({super.key});

  @override
  State<AgentsFlutterExampleApp> createState() =>
      _AgentsFlutterExampleAppState();
}

class _AgentsFlutterExampleAppState extends State<AgentsFlutterExampleApp> {
  late final ConfiguredAgentsManager _manager;
  late final ConfiguredAgentFactory _factory;

  @override
  void initState() {
    super.initState();
    final keyValueStore = SharedPreferencesKeyValueStore();
    _manager = ConfiguredAgentsManager(
      sources: ModelSourceStore(keyValueStore),
      agents: AgentConfigurationStore(keyValueStore),
      secrets: FlutterSecureSecretStore(),
    );
    _factory = ConfiguredAgentFactory(_manager);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'agents_flutter example',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      textTheme: GoogleFonts.outfitTextTheme(),
      useMaterial3: true,
    ),
    home: HomeScreen(manager: _manager, factory: _factory),
  );
}

/// Lists configured agents and opens the settings surface and chat.
class HomeScreen extends StatefulWidget {
  /// Creates a [HomeScreen].
  const HomeScreen({required this.manager, required this.factory, super.key});

  /// The configuration coordinator.
  final ConfiguredAgentsManager manager;

  /// Resolves saved agents into runnable agents.
  final ConfiguredAgentFactory factory;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<void> _ready;

  // Bumped whenever the saved agents may have changed (e.g. after returning
  // from settings) to force [_AgentList] to rebuild from storage.
  int _agentListToken = 0;

  @override
  void initState() {
    super.initState();
    _ready = _seedIfNeeded();
  }

  Future<void> _seedIfNeeded() async {
    if (_seedApiKey.trim().isEmpty) return;
    final existing = await widget.manager.sources.listSources();
    if (existing.isNotEmpty) return;

    const sourceId = 'seed-anthropic';
    const modelId = 'seed-anthropic-model';
    await widget.manager.saveSource(
      const ModelSourceConfig(
        id: sourceId,
        providerType: ProviderType.anthropic,
        displayName: 'Anthropic (seeded)',
      ),
      apiKey: _seedApiKey,
    );
    await widget.manager.saveModel(
      const ModelConfig(
        id: modelId,
        sourceId: sourceId,
        modelId: _seedModel,
        displayName: 'Claude',
      ),
    );
    await widget.manager.saveAgent(
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(manager: widget.manager),
      ),
    );
    if (mounted) {
      setState(() => _agentListToken++);
    }
  }

  void _openChat(SavedAgentConfig agent) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(agent: agent, factory: widget.factory),
      ),
    );
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
          manager: widget.manager,
          onSelected: _openChat,
          onManage: _openSettings,
        );
      },
    ),
  );
}

class _AgentList extends StatefulWidget {
  const _AgentList({
    required this.manager,
    required this.onSelected,
    required this.onManage,
    super.key,
  });

  final ConfiguredAgentsManager manager;
  final void Function(SavedAgentConfig agent) onSelected;
  final VoidCallback onManage;

  @override
  State<_AgentList> createState() => _AgentListState();
}

class _AgentListState extends State<_AgentList> {
  late Future<List<SavedAgentConfig>> _agents;

  @override
  void initState() {
    super.initState();
    _agents = widget.manager.agents.listAgents();
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
  const SettingsScreen({required this.manager, super.key});

  /// The configuration coordinator.
  final ConfiguredAgentsManager manager;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Manage agents')),
    body: Column(
      children: [
        const _WebSecurityNotice(),
        Expanded(child: ConfiguredAgentsView(manager: manager)),
      ],
    ),
  );
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
  const ChatScreen({required this.agent, required this.factory, super.key});

  /// The saved agent to chat with.
  final SavedAgentConfig agent;

  /// Resolves the saved agent into a runnable agent.
  final ConfiguredAgentFactory factory;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final Future<AgentLlmProvider> _providerFuture;
  AgentLlmProvider? _provider;

  @override
  void initState() {
    super.initState();
    _providerFuture = _createProvider();
  }

  Future<AgentLlmProvider> _createProvider() async {
    final agent = await widget.factory.createAgent(widget.agent);
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

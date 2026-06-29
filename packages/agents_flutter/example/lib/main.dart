// ignore_for_file: non_constant_identifier_names

import 'dart:async';

import 'package:agents/agents.dart';
import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart' as ai;
import 'package:extensions/system.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const AgentsFlutterExampleApp());
}

class AgentsFlutterExampleApp extends StatelessWidget {
  const AgentsFlutterExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'agents_flutter example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        textTheme: GoogleFonts.googleSansCodeTextTheme(),
        useMaterial3: true,
      ),
      home: const ChatDemoScreen(),
    );
  }
}

class ChatDemoScreen extends StatefulWidget {
  const ChatDemoScreen({super.key});

  @override
  State<ChatDemoScreen> createState() => _ChatDemoScreenState();
}

class _ChatDemoScreenState extends State<ChatDemoScreen> {
  late final AgentLlmProvider _provider;

  @override
  void initState() {
    super.initState();
    // This demo uses a keyless fake agent so it runs with no API credentials.
    // With a real ChatClient, swap in a FlutterHarnessAgent to get the full
    // harness plus the Flutter device-capability providers and tools:
    //
    //   final agent = chatClient.asFlutterHarnessAgent(
    //     1050000, // model context-window tokens
    //     128000,  // model per-response output tokens
    //     options: FlutterHarnessAgentOptions()..enableLocation = true,
    //   );
    //
    // Or register it through DI:
    //
    //   services.addFlutter((flutter) => flutter.useFlutterHarnessAgent(
    //     configure: (options) => options.enableNetworkInfo = true,
    //   ));
    _provider = AgentLlmProvider(
      agent: _DemoAgent(),
      session: _DemoAgentSession(),
    );
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('agents_flutter chat UI'),
        actions: [
          IconButton(
            tooltip: 'Clear chat',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _provider.history = const [],
          ),
        ],
      ),
      body: LlmChatView(
        provider: _provider,
        style: _demoStyle(),
        welcomeMessage: 'Ask the demo agent anything.',
        suggestions: const [
          'Show me a markdown response',
          'What do attachments look like?',
          'Stream a short checklist',
        ],
        enableVoiceNotes: false,
      ),
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

class _DemoAgent extends AIAgent {
  @override
  String? get name => 'Demo Agent';

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async {
    return _DemoAgentSession();
  }

  @override
  Future<AgentResponse> runCore(
    Iterable<ai.ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    return AgentResponse(
      message: ai.ChatMessage.fromText(
        ai.ChatRole.assistant,
        _composeReply(messages),
      ),
    );
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ai.ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final reply = _composeReply(messages);
    for (final chunk in _chunks(reply, 28)) {
      await Future<void>.delayed(const Duration(milliseconds: 35));
      yield AgentResponseUpdate(role: ai.ChatRole.assistant, content: chunk);
    }
  }

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async {
    return '{}';
  }

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async {
    return _DemoAgentSession();
  }

  String _composeReply(Iterable<ai.ChatMessage> messages) {
    final message = messages.last;
    final prompt = message.text.trim();
    final dataCount = message.contents.whereType<ai.DataContent>().length;
    final linkCount = message.contents.whereType<ai.UriContent>().length;

    return '''
## Demo response

You sent:

> ${prompt.isEmpty ? '(empty prompt)' : prompt}

This came through the real `AgentLlmProvider` adapter:

- Text content: `${prompt.length}` characters
- File or image attachments: `$dataCount`
- Link attachments: `$linkCount`

Try adding an attachment or selecting another suggestion to see the transcript update.
''';
  }

  Iterable<String> _chunks(String text, int size) sync* {
    for (var index = 0; index < text.length; index += size) {
      final end = index + size > text.length ? text.length : index + size;
      yield text.substring(index, end);
    }
  }
}

class _DemoAgentSession extends AgentSession {
  _DemoAgentSession() : super(AgentSessionStateBag(null));
}

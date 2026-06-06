import 'dart:io';
import 'dart:math';

import 'package:extensions/ai.dart';
import 'package:path/path.dart' as p;

import '../abstractions/ai_agent.dart';
import '../abstractions/ai_context_provider.dart';
import '../abstractions/delegating_ai_agent.dart';
import '../abstractions/in_memory_chat_history_provider.dart';
import '../abstractions/in_memory_chat_history_provider_options.dart';
import '../ai/agent_extensions.dart';
import '../ai/ai_context_provider_decorators/ai_context_provider_chat_client_builder_extensions.dart';
import '../ai/chat_client/chat_client_agent.dart';
import '../ai/chat_client/chat_client_agent_options.dart';
import '../ai/chat_client/chat_client_builder_extensions.dart';
import '../ai/compaction/chat_strategy_extensions.dart';
import '../ai/compaction/compaction_provider.dart';
import '../ai/compaction/context_window_compaction_strategy.dart';
import '../ai/harness/agent_mode/agent_mode_provider.dart';
import '../ai/harness/background_agents/background_agents_provider.dart';
import '../ai/harness/file_access/file_access_provider.dart';
import '../ai/harness/file_memory/file_memory_provider.dart';
import '../ai/harness/file_memory/file_memory_state.dart';
import '../ai/harness/file_store/file_system_agent_file_store.dart';
import '../ai/harness/todo/todo_provider.dart';
import '../ai/harness/tool_approval/tool_approval_agent_builder_extensions.dart';
import '../ai/open_telemetry_agent_builder_extensions.dart';
import '../ai/skills/agent_skills_provider.dart';
import '../tools/shell/shell_environment_provider.dart';
import '../tools/shell/shell_executor.dart';
import 'harness_agent_options.dart';

/// A pre-configured agent that wraps a [ChatClient] with function invocation,
/// per-service-call chat history persistence, compaction, and the default
/// harness context providers.
final class HarnessAgent extends DelegatingAIAgent {
  /// Built-in default system instructions used when no harness instructions
  /// are provided.
  static const String defaultInstructions = '''
You are a helpful AI assistant that uses tools to complete tasks.

## General guidelines

- Think through the task before acting. Break complex work into clear steps.
- Use the tools available to you to gather information, perform actions, and verify results.
- Explain your reasoning and thought process as you work through tasks.
- Explain what you learned and what you are going to do next between tool calls, so the user can follow along with your thought process.
- Avoid making more than 4 tool calls in a row without explaining what you are doing.
- If a tool call fails or returns unexpected results, adapt your approach rather than repeating the same call.
- When you have completed the task, present a clear and concise summary of what you did and what you found.
''';

  /// Creates a harness agent around [chatClient].
  HarnessAgent(
    ChatClient chatClient,
    int maxContextWindowTokens,
    int maxOutputTokens, {
    HarnessAgentOptions? options,
  }) : super(
         _buildAgent(
           chatClient,
           maxContextWindowTokens,
           maxOutputTokens,
           options,
         ),
       );

  static AIAgent _buildAgent(
    ChatClient chatClient,
    int maxContextWindowTokens,
    int maxOutputTokens,
    HarnessAgentOptions? options,
  ) {
    final innerAgent = _buildInnerAgent(
      chatClient,
      maxContextWindowTokens,
      maxOutputTokens,
      options,
    );
    final builder = innerAgent.asBuilder();

    if (options?.disableToolApproval != true) {
      builder.useToolApproval();
    }
    if (options?.disableOpenTelemetry != true) {
      builder.useOpenTelemetry(sourceName: options?.openTelemetrySourceName);
    }

    return builder.build();
  }

  static ChatClientAgent _buildInnerAgent(
    ChatClient chatClient,
    int maxContextWindowTokens,
    int maxOutputTokens,
    HarnessAgentOptions? options,
  ) {
    final compactionStrategy = ContextWindowCompactionStrategy(
      maxContextWindowTokens,
      maxOutputTokens,
    );
    final chatHistoryProvider =
        options?.chatHistoryProvider ??
        InMemoryChatHistoryProvider(
          options: InMemoryChatHistoryProviderOptions()
            ..chatReducer = compactionStrategy.asChatReducer(),
        );

    final harnessInstructions =
        options?.harnessInstructions ?? defaultInstructions;
    final agentInstructions = options?.chatOptions?.instructions;
    final instructions = _combineInstructions(
      harnessInstructions,
      agentInstructions,
    );
    final chatOptions = _buildChatOptions(
      options,
      instructions,
      maxOutputTokens,
    );
    final compactionProvider = CompactionProvider(compactionStrategy);
    final contextProviders = _buildContextProviders(options);

    final builder = ChatClientBuilder(chatClient);
    builder.usePerServiceCallChatHistoryPersistence();
    builder.use((innerClient) {
      final functionClient = FunctionInvokingChatClient(innerClient);
      final maxIterations = options?.maximumIterationsPerRequest;
      if (maxIterations != null) {
        functionClient.maximumIterationsPerRequest = maxIterations;
      }
      return functionClient;
    });
    builder.useAIContextProviders([compactionProvider]);

    return builder.buildAIAgent(
      options: ChatClientAgentOptions()
        ..id = options?.id
        ..name = options?.name
        ..description = options?.description
        ..chatOptions = chatOptions
        ..chatHistoryProvider = chatHistoryProvider
        ..aiContextProviders = contextProviders
        ..useProvidedChatClientAsIs = true
        ..requirePerServiceCallChatHistoryPersistence = true
        ..warnOnChatHistoryProviderConflict = false
        ..throwOnChatHistoryProviderConflict = false,
    );
  }

  static String _combineInstructions(
    String harnessInstructions,
    String? agentInstructions,
  ) {
    final hasHarness = harnessInstructions.trim().isNotEmpty;
    final hasAgent = agentInstructions?.trim().isNotEmpty == true;
    if (!hasHarness && !hasAgent) {
      return harnessInstructions;
    }
    if (!hasHarness) {
      return agentInstructions!;
    }
    if (!hasAgent) {
      return harnessInstructions;
    }
    return '$harnessInstructions\n\n$agentInstructions';
  }

  static ChatOptions _buildChatOptions(
    HarnessAgentOptions? options,
    String instructions,
    int maxOutputTokens,
  ) {
    final result = options?.chatOptions?.clone() ?? ChatOptions();
    result.instructions = instructions;
    result.maxOutputTokens ??= maxOutputTokens;

    if (options?.disableWebSearch != true) {
      (result.tools ??= <AITool>[]).add(HostedWebSearchTool());
    }

    final shellExecutor = options?.shellExecutor;
    if (shellExecutor != null) {
      (result.tools ??= <AITool>[]).add(_asShellFunction(shellExecutor));
    }

    return result;
  }

  static List<AIContextProvider> _buildContextProviders(
    HarnessAgentOptions? options,
  ) {
    final providers = <AIContextProvider>[];

    if (options?.disableTodoProvider != true) {
      providers.add(TodoProvider());
    }
    if (options?.disableAgentModeProvider != true) {
      providers.add(
        AgentModeProvider(options: options?.agentModeProviderOptions),
      );
    }
    if (options?.disableFileMemory != true) {
      final fileMemoryStore =
          options?.fileMemoryStore ??
          FileSystemAgentFileStore(
            p.join(Directory.systemTemp.path, 'agent-file-memory'),
          );
      providers.add(
        FileMemoryProvider(
          fileMemoryStore,
          stateInitializer: (_) =>
              FileMemoryState()..workingFolder = _newWorkingFolder(),
        ),
      );
    }
    if (options?.disableFileAccess != true) {
      final fileAccessStore =
          options?.fileAccessStore ??
          FileSystemAgentFileStore(
            p.join(Directory.systemTemp.path, 'working'),
          );
      providers.add(FileAccessProvider(fileAccessStore));
    }
    if (options?.disableAgentSkillsProvider != true) {
      providers.add(
        options?.agentSkillsSource != null
            ? AgentSkillsProvider(source: options!.agentSkillsSource)
            : AgentSkillsProvider(skillPath: Directory.systemTemp.path),
      );
    }

    final backgroundAgents = options?.backgroundAgents?.toList();
    if (backgroundAgents != null && backgroundAgents.isNotEmpty) {
      providers.add(
        BackgroundAgentsProvider(
          backgroundAgents,
          options: options?.backgroundAgentsProviderOptions,
        ),
      );
    }

    final shellExecutor = options?.shellExecutor;
    if (shellExecutor != null) {
      providers.add(
        ShellEnvironmentProvider(
          shellExecutor,
          options: options?.shellEnvironmentProviderOptions,
        ),
      );
    }

    final userProviders = options?.aiContextProviders;
    if (userProviders != null) {
      providers.addAll(userProviders);
    }

    return providers;
  }

  static AIFunction _asShellFunction(ShellExecutor shellExecutor) {
    final inner = AIFunctionFactory.create(
      name: 'run_shell',
      description:
          'Runs a shell command and returns its stdout, stderr, and exit code.',
      parametersSchema: const {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'The shell command to execute.',
          },
        },
        'required': ['command'],
      },
      callback: (arguments, {cancellationToken}) async {
        final command = (arguments['command'] ?? '').toString();
        final result = await shellExecutor.runAsync(
          command,
          cancellationToken: cancellationToken,
        );
        return result.formatForModel();
      },
    );

    return ApprovalRequiredAIFunction(inner);
  }

  static String _newWorkingFolder() {
    final now = DateTime.now().toUtc();
    final timestamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}'
        '${now.microsecond.toString().padLeft(6, '0')}';
    final suffix = Random().nextInt(0x7fffffff).toRadixString(16);
    return '${timestamp}_$suffix';
  }
}

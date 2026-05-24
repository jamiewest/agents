import 'package:extensions/ai.dart';

import '../../abstractions/ai_agent.dart';
import '../../abstractions/ai_context_provider.dart';
import '../../abstractions/chat_history_provider.dart';
import '../../ai/harness/agent_mode/agent_mode_provider_options.dart';
import '../../ai/harness/background_agents/background_agents_provider_options.dart';
import '../../ai/harness/file_store/agent_file_store.dart';
import '../../ai/skills/agent_skills_source.dart';
import '../../tools/shell/shell_environment_provider_options.dart';
import '../../tools/shell/shell_executor.dart';

/// Configuration options for a `HarnessAgent`.
class HarnessAgentOptions {
  /// Creates configuration options for a `HarnessAgent`.
  HarnessAgentOptions({
    this.id,
    this.name,
    this.description,
    this.chatOptions,
    this.harnessInstructions,
    this.chatHistoryProvider,
    this.aiContextProviders,
    this.maximumIterationsPerRequest,
    this.disableToolApproval = false,
    this.disableFileMemory = false,
    this.fileMemoryStore,
    this.disableFileAccess = false,
    this.fileAccessStore,
    this.disableWebSearch = false,
    this.disableTodoProvider = false,
    this.disableAgentModeProvider = false,
    this.agentModeProviderOptions,
    this.disableAgentSkillsProvider = false,
    this.agentSkillsSource,
    this.disableOpenTelemetry = false,
    this.openTelemetrySourceName,
    this.backgroundAgents,
    this.backgroundAgentsProviderOptions,
    this.shellExecutor,
    this.shellEnvironmentProviderOptions,
  });

  /// Optional agent identifier.
  String? id;

  /// Optional agent display name.
  String? name;

  /// Optional agent description.
  String? description;

  /// Additional chat options, such as tools and agent-specific instructions.
  ChatOptions? chatOptions;

  /// Harness-level instructions that guide general tool usage and behavior.
  ///
  /// When `null`, the harness agent default instructions are used. Set to an
  /// empty string to omit harness instructions entirely.
  String? harnessInstructions;

  /// Provider used for storing chat history.
  ChatHistoryProvider? chatHistoryProvider;

  /// Additional context providers to include in the agent pipeline.
  Iterable<AIContextProvider>? aiContextProviders;

  /// Maximum function-invocation loop iterations per request.
  int? maximumIterationsPerRequest;

  /// When `true`, disables the tool approval wrapper.
  bool disableToolApproval;

  /// When `true`, disables file memory.
  bool disableFileMemory;

  /// Custom file store for file memory.
  AgentFileStore? fileMemoryStore;

  /// When `true`, disables file access.
  bool disableFileAccess;

  /// Custom file store for file access.
  AgentFileStore? fileAccessStore;

  /// When `true`, disables the hosted web-search tool.
  bool disableWebSearch;

  /// When `true`, disables the todo context provider.
  bool disableTodoProvider;

  /// When `true`, disables the agent mode context provider.
  bool disableAgentModeProvider;

  /// Custom options for the agent mode context provider.
  AgentModeProviderOptions? agentModeProviderOptions;

  /// When `true`, disables the agent skills context provider.
  bool disableAgentSkillsProvider;

  /// Custom skills source for the agent skills context provider.
  AgentSkillsSource? agentSkillsSource;

  /// When `true`, disables OpenTelemetry instrumentation.
  bool disableOpenTelemetry;

  /// OpenTelemetry source name used by the instrumentation wrapper.
  String? openTelemetrySourceName;

  /// Background agents available for delegation.
  Iterable<AIAgent>? backgroundAgents;

  /// Optional configuration for the background agents context provider.
  BackgroundAgentsProviderOptions? backgroundAgentsProviderOptions;

  /// Shell executor used to enable shell tools and environment context.
  ShellExecutor? shellExecutor;

  /// Optional configuration for the shell environment context provider.
  ShellEnvironmentProviderOptions? shellEnvironmentProviderOptions;
}

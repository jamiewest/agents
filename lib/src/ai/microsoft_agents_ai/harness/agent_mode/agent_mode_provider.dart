import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_session_state_bag.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/provider_session_state_t_state_.dart';
import '../../agent_json_utilities.dart';
import 'agent_mode_provider_options.dart';
import 'agent_mode_state.dart';

/// An [AIContextProvider] that tracks the agent's operating mode (e.g.,
/// "plan" or "execute") in the session state and provides tools for querying
/// and switching modes.
///
/// Remarks: The [AgentModeProvider] enables agents to operate in distinct
/// modes during long-running complex tasks. The current mode is persisted in
/// the session's [AgentSessionStateBag] and is included in the instructions
/// provided to the agent on each invocation. The set of available modes is
/// configurable via [Modes]. By default, two modes are provided: `"plan"`
/// (interactive planning) and `"execute"` (autonomous execution). This
/// provider exposes the following tools to the agent: `AgentMode_Set` —
/// Switch the agent's operating mode. `AgentMode_Get` — Retrieve the agent's
/// current operating mode. Public helper methods [AgentSession)] and
/// [String)] allow external code to programmatically read and change the
/// mode.
class AgentModeProvider extends AIContextProvider {
  /// Initializes a new instance of the [AgentModeProvider] class.
  ///
  /// [options] Optional settings that control provider behavior. When `null`,
  /// defaults are used.
  AgentModeProvider({AgentModeProviderOptions? options = null}) {
    this._modes = options?.modes ?? s_defaultModes;
    if (this._modes.length == 0) {
      throw ArgumentError("At least one mode must be configured.", 'options');
    }
    this._instructions = options?.instructions ?? DefaultInstructions;
    this._validModeNames = Set<String>();
    var modeNamesList = List<String>(this._modes.length);
    for (var i = 0; i < this._modes.length; i++) {
      var mode = this._modes[i];
      if (mode == null) {
        throw ArgumentError('Configured mode at index ${i} must not be null.', 'options');
      }
      if ((mode.name == null || mode.name.isEmpty)) {
        throw ArgumentError(
          'Configured mode at index ${i} must have a non-empty name.',
          'options',
        );
      }
      if (!this._validModeNames.add(mode.name)) {
        throw ArgumentError(
          'Configured modes contain a duplicate mode name \"${mode.name}\".',
          'options',
        );
      }
      modeNamesList.add(mode.name);
    }
    this._modeNamesDisplay = \"", modeNamesList.join("\");
    this._defaultMode = options?.defaultMode ?? modeNamesList[0];
    if (!this._validModeNames.contains(this._defaultMode)) {
      throw ArgumentError(
        'Default mode \"${this._defaultMode}\" is! in the configured modes list.',
        'options',
      );
    }
    this._sessionState = ProviderSessionState<AgentModeState>(
            (_) => agentModeState(),
            this.runtimeType.toString(),
            AgentJsonUtilities.defaultOptions);
  }

  static final List<AgentMode> s_defaultModes;

  late final ProviderSessionState<AgentModeState> _sessionState;

  late final List<AgentMode> _modes;

  late final String _defaultMode;

  late final String? _instructions;

  late final Set<String> _validModeNames;

  late final String _modeNamesDisplay;

  List<String>? _stateKeys;

  List<String> get stateKeys {
    return this._stateKeys ??= [this._sessionState.stateKey];
  }

  /// Gets the current operating mode from the session state.
  ///
  /// Returns: The current mode String.
  ///
  /// [session] The agent session to read the mode from.
  String getMode(AgentSession? session) {
    return this._sessionState.getOrInitializeState(session).currentMode;
  }

  /// Sets the operating mode in the session state.
  ///
  /// [session] The agent session to update the mode in.
  ///
  /// [mode] The new mode to set.
  void setMode(AgentSession? session, String mode, ) {
    this.validateMode(mode);
    var state = this._sessionState.getOrInitializeState(session);
    var previousMode = state.currentMode;
    state.currentMode = mode;
    if (!(previousMode == mode)) {
      state.previousModeForNotification = previousMode;
    }
    this._sessionState.saveState(session, state);
  }

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context,
    {CancellationToken? cancellationToken, },
  ) {
    var state = this._sessionState.getOrInitializeState(context.session);
    var instructions = this.buildInstructions(state.currentMode);
    var aiContext = AIContext();
    if (state.previousModeForNotification != null) {
      var previousMode = state.previousModeForNotification;
      state.previousModeForNotification = null;
      aiContext.messages =
            [
                ChatMessage.fromText(ChatRole.user, '[Mode changed: The operating mode has been switched from \"${previousMode}\" to \"${state.currentMode}\". You must now adjust your behavior to match the \"${state.currentMode}\" mode.]',),
            ];
    }
    return Future<AIContext>(aiContext);
  }

  String buildInstructions(String currentMode) {
    var modesListBuilder = StringBuffer();
    for (final mode in this._modes) {
      modesListBuilder.writeln('- \"${mode.name}\": ${mode.description}');
    }
    var modesListText = modesListBuilder.toString();
    return stringBuilder(this._instructions)
            .replaceAll("{available_modes}", modesListText)
            .replaceAll("{current_mode}", currentMode)
            .toString();
  }

  void validateMode(String mode) {
    if (!this._validModeNames.contains(mode)) {
      throw ArgumentError(
        'Invalid mode: \"${mode}\". Supported modes are: \"${this._modeNamesDisplay}\".',
        'mode',
      );
    }
  }

  List<AITool> createTools(AgentModeState state, AgentSession? session, ) {
    var serializerOptions = AgentJsonUtilities.defaultOptions;
    return [
            AIFunctionFactory.create(
                (String mode) =>
                {
                    this.validateMode(mode);

                    state.currentMode = mode;
                    this._sessionState.saveState(session, state);
                    return 'Mode changed to \"${mode}\".';
                },
                AIFunctionFactoryOptions()\".',
                    SerializerOptions = serializerOptions,
                }),

            AIFunctionFactory.create(
                () => state.currentMode,
                AIFunctionFactoryOptions()),
        ];
}
 }

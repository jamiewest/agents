import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
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
/// the session state and is included in the instructions provided to the agent
/// on each invocation.
class AgentModeProvider extends AIContextProvider {
  /// Initializes a new instance of the [AgentModeProvider] class.
  AgentModeProvider({AgentModeProviderOptions? options}) {
    _modes = options?.modes ?? defaultModes;
    if (_modes.isEmpty) {
      throw ArgumentError('At least one mode must be configured.', 'options');
    }

    _instructions = options?.instructions ?? defaultInstructions;

    _validModeNames = <String>{};
    final modeNamesList = <String>[];
    for (var i = 0; i < _modes.length; i++) {
      final mode = _modes[i];
      if (mode == null) {
        throw ArgumentError(
          'Configured mode at index $i must not be null.',
          'options',
        );
      }

      if (mode.name.isEmpty) {
        throw ArgumentError(
          'Configured mode at index $i must have a non-empty name.',
          'options',
        );
      }

      if (!_validModeNames.add(mode.name)) {
        throw ArgumentError(
          'Configured modes contain a duplicate mode name "${mode.name}".',
          'options',
        );
      }

      modeNamesList.add(mode.name);
    }

    _modeNamesDisplay = modeNamesList.join('", "');
    _defaultMode = options?.defaultMode ?? modeNamesList[0];
    if (!_validModeNames.contains(_defaultMode)) {
      throw ArgumentError(
        'Default mode "$_defaultMode" is not in the configured modes list.',
        'options',
      );
    }

    _sessionState = ProviderSessionState<AgentModeState>(
      (_) => AgentModeState()..currentMode = _defaultMode,
      runtimeType.toString(),
      JsonSerializerOptions: AgentJsonUtilities.defaultOptions,
    );
  }

  static const String defaultInstructions = '''
## Agent Mode

You can operate in different modes. Depending on the mode you are in, you will be required to follow different processes.

Use the AgentMode_Get tool to check your current operating mode.
Use the AgentMode_Set tool to switch between modes as your work progresses. Only use AgentMode_Set if the user explicitly instructs/allows you to change modes.

{available_modes}

You are currently operating in the {current_mode} mode.
''';

  static final List<AgentMode> defaultModes = [
    AgentMode(
      'plan',
      'Use this mode when analyzing requirements, breaking down tasks, and creating plans. This is the interactive mode - ask clarifying questions, discuss options, and get user approval before proceeding.',
    ),
    AgentMode(
      'execute',
      'Use this mode when carrying out approved plans. Work autonomously using your best judgement - do not ask the user questions or wait for feedback. Make reasonable decisions on your own so that there is a complete, useful result when the user returns. If you encounter ambiguity, choose the most reasonable option and note your choice.',
    ),
  ];

  late final ProviderSessionState<AgentModeState> _sessionState;
  late final List<AgentMode?> _modes;
  late final String _defaultMode;
  late final String _instructions;
  late final Set<String> _validModeNames;
  late final String _modeNamesDisplay;
  List<String>? _stateKeys;

  @override
  List<String> get stateKeys => _stateKeys ??= [_sessionState.stateKey];

  /// Gets the current operating mode from the session state.
  String getMode(AgentSession? session) {
    return _sessionState.getOrInitializeState(session).currentMode;
  }

  /// Sets the operating mode in the session state.
  void setMode(AgentSession? session, String mode) {
    validateMode(mode);

    final state = _sessionState.getOrInitializeState(session);
    final previousMode = state.currentMode;
    state.currentMode = mode;

    if (previousMode != mode) {
      state.previousModeForNotification = previousMode;
    }

    _sessionState.saveState(session, state);
  }

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) {
    final state = _sessionState.getOrInitializeState(context.session);
    final instructions = buildInstructions(state.currentMode);

    final aiContext = AIContext()
      ..instructions = instructions
      ..tools = createTools(state, context.session);

    if (state.previousModeForNotification != null) {
      final previousMode = state.previousModeForNotification!;
      state.previousModeForNotification = null;

      aiContext.messages = [
        ChatMessage.fromText(
          ChatRole.user,
          '[Mode changed: The operating mode has been switched from "$previousMode" to "${state.currentMode}". You must now adjust your behavior to match the "${state.currentMode}" mode.]',
        ),
      ];
    }

    return Future.value(aiContext);
  }

  String buildInstructions(String currentMode) {
    final modesListBuilder = StringBuffer();
    for (final mode in _modes) {
      modesListBuilder.writeln('- "${mode!.name}": ${mode.description}');
    }
    final modesListText = modesListBuilder.toString();
    return _instructions
        .replaceAll('{available_modes}', modesListText)
        .replaceAll('{current_mode}', currentMode);
  }

  void validateMode(String mode) {
    if (!_validModeNames.contains(mode)) {
      throw ArgumentError(
        'Invalid mode: "$mode". Supported modes are: "$_modeNamesDisplay".',
        'mode',
      );
    }
  }

  List<AITool> createTools(AgentModeState state, AgentSession? session) {
    return [
      AIFunctionFactory.create(
        name: 'AgentMode_Set',
        description:
            'Switch the agent\'s operating mode. Supported modes: "$_modeNamesDisplay".',
        parametersSchema: _objectSchema({
          'mode': 'The operating mode to switch to.',
        }),
        callback: (arguments, {cancellationToken}) async {
          final mode = _getRequiredString(arguments, 'mode');
          validateMode(mode);

          state.currentMode = mode;
          _sessionState.saveState(session, state);
          return 'Mode changed to "$mode".';
        },
      ),
      AIFunctionFactory.create(
        name: 'AgentMode_Get',
        description: 'Get the agent\'s current operating mode.',
        callback: (arguments, {cancellationToken}) async => state.currentMode,
      ),
    ];
  }

  static String _getRequiredString(AIFunctionArguments arguments, String name) {
    final value = arguments[name];
    if (value is String) {
      return value;
    }
    throw ArgumentError.value(value, name, 'Expected a string value.');
  }

  static Map<String, dynamic> _objectSchema(Map<String, String> properties) {
    return {
      'type': 'object',
      'properties': {
        for (final entry in properties.entries)
          entry.key: {'description': entry.value},
      },
      'required': properties.keys.toList(),
    };
  }
}

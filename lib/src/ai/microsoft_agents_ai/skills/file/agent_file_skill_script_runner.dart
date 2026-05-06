/// Function for running file-based skill scripts.
///
/// Remarks: Implementations determine the execution strategy (e.g., local
/// subprocess, hosted code execution environment). The `arguments` parameter
/// preserves the raw JSON sent by the caller, in the shape described by
/// [ParametersSchema].
///
/// Returns: The script execution result.
///
/// [skill] The skill that owns the script.
///
/// [script] The file-based script to run.
///
/// [arguments] Raw JSON arguments for the script, in the shape described by
/// [ParametersSchema].
///
/// [serviceProvider] Optional service provider for dependency injection.
///
/// [cancellationToken] Cancellation token.
typedef AgentFileSkillScriptRunner = void Function();

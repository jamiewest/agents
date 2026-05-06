import 'package:extensions/logging.dart';
import 'ai_agent_builder.dart';
import 'logging_agent.dart';
import '../../func_typedefs.dart';

/// Provides extension methods for adding logging support to [AIAgentBuilder]
/// instances.
extension LoggingAgentBuilderExtensions on AIAgentBuilder {
  /// Adds logging to the agent pipeline, enabling detailed observability of
/// agent operations.
///
/// Remarks: When the employed [Logger] enables [Trace], the contents of
/// messages, options, and responses are logged. These may contain sensitive
/// application data. [Trace] is disabled by default and should never be
/// enabled in a production environment. Messages and options are not logged
/// at other logging levels. If the resolved or provided [LoggerFactory] is
/// [NullLoggerFactory], this will be a no-op where logging will be
/// effectively disabled. In this case, the [LoggingAgent] will not be added.
///
/// Returns: The [AIAgentBuilder] with logging support added, enabling method
/// chaining.
///
/// [builder] The [AIAgentBuilder] to which logging support will be added.
///
/// [loggerFactory] An optional [LoggerFactory] used to create a logger with
/// which logging should be performed. If not supplied, a required instance
/// will be resolved from the service provider.
///
/// [configure] An optional callback that provides additional configuration of
/// the [LoggingAgent] instance. This allows for fine-tuning logging behavior
/// such as customizing JSON serialization options.
AIAgentBuilder useLogging({LoggerFactory? loggerFactory, Action<LoggingAgent>? configure, }) {
return builder.use((innerAgent, services) {
        
            loggerFactory ??= services.getRequiredService<LoggerFactory>();

            // If the factory we resolve is for the null logger, the LoggingAgent will end up
            // being an expensive nop, so skip adding it and just return the inner agent.
            if (loggerFactory == NullLoggerFactory.instance)
            {
                return innerAgent;
            }

            LoggingAgent agent = new(innerAgent, loggerFactory.createLogger('LoggingAgent'));
            configure?.invoke(agent);
            return agent;
        });
 }
 }

import 'package:extensions/logging.dart';

import '../func_typedefs.dart';
import 'ai_agent_builder.dart';
import 'logging_agent.dart';

/// Provides extension methods for adding logging support to [AIAgentBuilder]
/// instances.
extension LoggingAgentBuilderExtensions on AIAgentBuilder {
  /// Adds logging to the agent pipeline.
  ///
  /// If a [NullLoggerFactory] is supplied or resolved, this is a no-op and the
  /// inner agent is returned unchanged, matching the upstream optimization.
  AIAgentBuilder useLogging({
    LoggerFactory? loggerFactory,
    Action1<LoggingAgent>? configure,
  }) {
    return useFactory((innerAgent, services) {
      final resolvedFactory =
          loggerFactory ??
          services.getServiceFromType(LoggerFactory) as LoggerFactory? ??
          NullLoggerFactory.instance;

      if (identical(resolvedFactory, NullLoggerFactory.instance)) {
        return innerAgent;
      }

      final agent = LoggingAgent(
        innerAgent,
        resolvedFactory.createLogger('LoggingAgent'),
      );
      configure?.call(agent);
      return agent;
    });
  }
}

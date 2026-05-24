/// Telemetry tag key constants for workflow observability.
abstract final class Tags {
  static const String workflowId = 'workflow.id';
  static const String workflowName = 'workflow.name';
  static const String workflowDescription = 'workflow.description';
  static const String workflowDefinition = 'workflow.definition';
  static const String buildErrorMessage = 'build.error.message';
  static const String buildErrorType = 'build.error.type';
  static const String errorType = 'error.type';
  static const String errorMessage = 'error.message';
  static const String sessionId = 'session.id';
  static const String executorId = 'executor.id';
  static const String executorType = 'executor.type';
  static const String executorInput = 'executor.input';
  static const String executorOutput = 'executor.output';
  static const String messageType = 'message.type';
  static const String messageContent = 'message.content';
  static const String edgeGroupType = 'edge_group.type';
  static const String messageSourceId = 'message.source_id';
  static const String messageTargetId = 'message.target_id';
  static const String edgeGroupDelivered = 'edge_group.delivered';
  static const String edgeGroupDeliveryStatus = 'edge_group.delivery_status';
}

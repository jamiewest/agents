import '../checkpointing/portable_message_envelope.dart';
import '../external_request.dart';

class RunnerStateData {
  const RunnerStateData(
    Set<String> instantiatedExecutors,
    Map<String, List<PortableMessageEnvelope>> queuedMessages,
    List<ExternalRequest> outstandingRequests,
  ) : instantiatedExecutors = instantiatedExecutors,
      queuedMessages = queuedMessages,
      outstandingRequests = outstandingRequests;

  final Set<String> instantiatedExecutors = instantiatedExecutors;

  final Map<String, List<PortableMessageEnvelope>> queuedMessages =
      queuedMessages;

  final List<ExternalRequest> outstandingRequests = outstandingRequests;
}

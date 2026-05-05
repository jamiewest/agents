// TODO: import not yet ported
import '../external_response.dart';

extension RequestPortExtensions on RequestPort {
  /// Attempts to process the incoming [ExternalResponse] as a response to a
/// request sent through the specified [RequestPort]. If the response is to a
/// different port, returns `false`. If the port matches, but the response
/// data cannot be interpreted as the expected response type, throws an
/// [InvalidOperationException]. Otherwise, returns `true`.
///
/// Returns: `true` if the response is for the specified port and the data
/// could be interpreted as the expected response type; otherwise, `false`.
///
/// [port] The request port through which the original request was sent.
///
/// [response] The candidate response to be processed
bool shouldProcessResponse(ExternalResponse response) {
if (!port.isResponsePort(response)) {
  return false;
}
if (!response.data.isType(port.response)) {
  throw port.createExceptionForType(response);
}
return true;
 }
bool isResponsePort(ExternalResponse response) {
return response.portInfo.portId == port.id;
 }
StateError createExceptionForType(ExternalResponse response) {
return new('Message type ${response.data.typeId} is! assignable to the response type ${port.response.name}' +
               ' of input port ${port.id}.');
 }
 }

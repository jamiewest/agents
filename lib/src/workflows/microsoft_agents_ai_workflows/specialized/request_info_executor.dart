import 'package:extensions/system.dart';
import '../execution/external_request_sink.dart';
import '../executor_options.dart';
import '../external_request.dart';
import '../portable_value.dart';
import '../protocol_builder.dart';
import '../workflow_context.dart';

class RequestInfoExecutor extends Executor {
  RequestInfoExecutor(RequestPort port, {bool? allowWrapped = null, }) : port = port {
    this._allowWrapped = allowWrapped;
  }

  final Map<String, ExternalRequest> _wrappedRequests = {};

  final RequestPort port;

  late ExternalRequestSink? requestSink;

  late final bool _allowWrapped;

  static ExecutorOptions get defaultOptions {
    return new()
    {
        // We need to be able to return the ExternalRequest/Result objects so they can be bubbled up
        // through the event system, but we do not want to forward the Request message.
        AutoSendMessageHandlerResultObject = false,
        AutoYieldOutputHandlerResultObject = false
    };
  }

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    return protocolBuilder.configureRoutes(ConfigureRoutes)
                              .sendsMessage<ExternalRequest>()
                              .sendsMessageType(this.port.response);
    /* TODO: unsupported node kind "unknown" */
    // void ConfigureRoutes(RouteBuilder routeBuilder)
    //         {
      //             routeBuilder = routeBuilder
      //                 // Handle incoming requests (as raw request payloads)
      //                 .AddHandlerUntyped(this.Port.Request, this.HandleAsync)
      //                 .AddCatchAll(this.HandleCatchAllAsync);
      //
      //             if (this._allowWrapped)
      //             {
        //                 routeBuilder = routeBuilder
        //                     .AddHandler<ExternalRequest, ExternalRequest>(this.HandleAsync);
        //             }
      //
      //             routeBuilder
      //                 // Handle incoming responses (as wrapped Response Object)
      //                 .AddHandler<ExternalResponse, ExternalResponse?>(this.HandleAsync);
      //         }
  }

  void attachRequestSink(ExternalRequestSink requestSink) {
    this.requestSink = requestSink;
  }

  Future<ExternalRequest?> handleCatchAll(
    PortableValue message,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) async  {
    var maybeRequest = message.asType(this.port.request);
    if (maybeRequest != null) {
      assert(this.port.request.isInstanceOfType(maybeRequest));
      var request = ExternalRequest.create(this.port, maybeRequest!);
      await this.requestSink!.post(request);
      return request;
    } else if (message.isValue(request)) {
      return await this.handleAsync(request, context, cancellationToken);
    }
    return null;
  }

  Future<ExternalRequest> handle(
    WorkflowContext context,
    CancellationToken cancellationToken,
    {ExternalRequest? message, },
  ) async  {
    // TODO(ai): implement dispatch
    throw UnimplementedError();
  }

  @override
  Future onCheckpointing(WorkflowContext context, {CancellationToken? cancellationToken, }) async  {
    await context.queueStateUpdate(WrappedRequestsStateKey,
                                            new Dictionary<String, ExternalRequest>(
                                              this._wrappedRequests,
                                              ,
                                            ),
                                            cancellationToken: cancellationToken);
    await super.onCheckpointingAsync(context, cancellationToken);
  }

  @override
  Future onCheckpointRestored(
    WorkflowContext context,
    {CancellationToken? cancellationToken, },
  ) async  {
    await super.onCheckpointRestoredAsync(context, cancellationToken);
    this._wrappedRequests.clear();
    var wrappedRequests = await context.readStateAsync<Map<String, ExternalRequest>>(
      WrappedRequestsStateKey,
      cancellationToken: cancellationToken,
    )
                          ?? [];
    for (final wrappedRequest in wrappedRequests) {
      this._wrappedRequests[wrappedRequest.key] = wrappedRequest.value;
    }
  }
}
class RequestPortOptions {
  RequestPortOptions();

}

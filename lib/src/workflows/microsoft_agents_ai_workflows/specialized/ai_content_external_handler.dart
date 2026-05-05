import 'package:extensions/system.dart';
import '../../../func_typedefs.dart';
import '../port_binding.dart';
import '../protocol_builder.dart';
import '../workflow_context.dart';
import '../../../map_extensions.dart';

class AIContentExternalHandler<TRequestContent,TResponseContent> {
  AIContentExternalHandler(
    ProtocolBuilder protocolBuilder,
    String portId,
    bool intercepted,
    Func3<TResponseContent, WorkflowContext, CancellationToken, Future> handler,
  ) : _portId = portId {
    var portBinding = null;
    protocolBuilder = protocolBuilder.configureRoutes((routeBuilder) => configureRoutes(routeBuilder, portBinding));
    this._portBinding = portBinding;
    if (intercepted) {
      protocolBuilder = protocolBuilder.sendsMessage<TRequestContent>();
    }
    /* TODO: unsupported node kind "unknown" */
    // void ConfigureRoutes(RouteBuilder routeBuilder, portBinding)
    //         {
      //             if (intercepted)
      //             {
        //                 portBinding = null;
        //                 routeBuilder.AddHandler(handler);
        //             }
      //             else
      //             {
        //                 routeBuilder.AddPortHandler<TRequestContent, TResponseContent>(portId, handler, portBinding);
        //             }
      //         }
  }

  late final PortBinding? _portBinding;

  final String _portId;

  late Map<String, TRequestContent> _pendingRequests;

  bool get hasPendingRequests {
    return !this._pendingRequests.isEmpty;
  }

  Future processRequestContents(
    Map<String, TRequestContent> requests,
    WorkflowContext context,
    {CancellationToken? cancellationToken, },
  ) {
    var requestTasks = from String requestId in requests.keys
                                         select this.processRequestContentAsync(
                                           requestId,
                                           requests[requestId],
                                           context,
                                           cancellationToken,
                                         )
                                                    .future;
    return Future.wait(requestTasks);
  }

  Future processRequestContent(
    String id,
    TRequestContent requestContent,
    WorkflowContext context,
    {CancellationToken? cancellationToken, },
  ) {
    if (!this._pendingRequests.tryAdd(id, requestContent)) {
      return Future.value();
    }
    return this.isIntercepted
             ? context.sendMessage(requestContent, cancellationToken: cancellationToken)
             : this._portBinding.postRequestAsync(
               requestContent,
               this.createExternalRequestId(id),
               cancellationToken,
             );
  }

  bool markRequestAsHandled(String id) {
    return this._pendingRequests.tryRemoveKey(id);
  }

  bool get isIntercepted {
    return this._portBinding == null;
  }

  String createExternalRequestId(String requestId) {
    return '${this._portId.length}:${this._portId}:${requestId}';
  }

  static String makeKey(String id) {
    return '${id}_PendingRequests';
  }

  Future onCheckpointing(
    String id,
    WorkflowContext context,
    {CancellationToken? cancellationToken, },
  ) async  {
    var pendingRequestsCopy = new(this._pendingRequests);
    await context.queueStateUpdate(
      makeKey(id),
      pendingRequestsCopy,
      cancellationToken: cancellationToken,
    )
                     ;
  }

  Future onCheckpointRestored(
    String id,
    WorkflowContext context,
    {CancellationToken? cancellationToken, },
  ) async  {
    var loadedState = await context.readStateAsync<Map<String, TRequestContent>>(
      makeKey(id),
      cancellationToken: cancellationToken,
    )
                         ;
    if (loadedState != null) {
      this._pendingRequests = new Map<String, TRequestContent>(loadedState);
    }
  }
}

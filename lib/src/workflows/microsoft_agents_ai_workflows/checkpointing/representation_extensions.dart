import '../edge.dart';
import '../executor_binding.dart';
import '../request_port.dart';
import 'direct_edge_info.dart';
import 'edge_info.dart';
import 'executor_info.dart';
import 'fan_in_edge_info.dart';
import 'fan_out_edge_info.dart';
import 'request_port_info.dart';
import 'type_id.dart';

extension ExecutorBindingRepresentationExtensions on ExecutorBinding {
  ExecutorInfo toExecutorInfo() {
    return ExecutorInfo(
      TypeId(assemblyName: '', typeName: executorType.toString()),
      id,
    );
  }
}

extension EdgeRepresentationExtensions on Edge {
  EdgeInfo toEdgeInfo() {
    return switch (kind) {
      EdgeKind.direct => DirectEdgeInfo(
        data: directEdgeData,
        hasCondition: directEdgeData?.condition != null,
        connection: directEdgeData?.connection,
      ),
      EdgeKind.fanOut => FanOutEdgeInfo(
        data: fanOutEdgeData,
        hasAssigner: fanOutEdgeData?.edgeAssigner != null,
        connection: fanOutEdgeData?.connection,
      ),
      EdgeKind.fanIn => FanInEdgeInfo(
        data: fanInEdgeData,
        connection: fanInEdgeData?.connection,
      ),
    };
  }
}

extension RequestPortRepresentationExtensions on RequestPort {
  RequestPortInfo toPortInfo() {
    return RequestPortInfo(
      TypeId(assemblyName: '', typeName: request.toString()),
      TypeId(assemblyName: '', typeName: response.toString()),
      id,
    );
  }
}

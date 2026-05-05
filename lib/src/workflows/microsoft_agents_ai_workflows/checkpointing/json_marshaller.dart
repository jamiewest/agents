import '../workflows_json_utilities.dart';
import 'checkpoint_info_converter.dart';
import 'edge_id_converter.dart';
import 'executor_identity_converter.dart';
import 'portable_value_converter.dart';
import 'scope_key_converter.dart';
import 'wire_marshaller.dart';
import '../../../json_stubs.dart';

class JsonMarshaller implements WireMarshaller<JsonElement> {
  JsonMarshaller({JsonSerializerOptions? serializerOptions = null}) {
    this._internalOptions = JsonSerializerOptions(WorkflowsJsonUtilities.defaultOptions);
    this._internalOptions.converters.add(portableValueConverter(this));
    this._internalOptions.converters.add(executorIdentityConverter());
    this._internalOptions.converters.add(scopeKeyConverter());
    this._internalOptions.converters.add(edgeIdConverter());
    this._internalOptions.converters.add(checkpointInfoConverter());
    this._externalOptions = serializerOptions;
  }

  late final JsonSerializerOptions _internalOptions;

  late final JsonSerializerOptions? _externalOptions;

  JsonTypeInfo lookupTypeInfo(Type type) {
    JsonTypeInfo? typeInfo;
    if (!this._internalOptions.tryGetTypeInfo(type)) {
      if (this._externalOptions == null ||
                !this._externalOptions.tryGetTypeInfo(type, typeInfo)) {
        throw StateError("No JSON type info is available for type ${type}.");
      }
    }
    return typeInfo;
  }

  @override
  JsonElement marshal({Object? value, Type? type, JsonElement? data, Type? targetType, }) {
    return JsonSerializer.serializeToElement(value, this.lookupTypeInfo(type));
  }
}

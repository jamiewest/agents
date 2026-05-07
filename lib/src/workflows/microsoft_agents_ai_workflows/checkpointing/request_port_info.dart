/// Serializable request port description.
class RequestPortInfo {
  /// Creates request port info.
  const RequestPortInfo({
    required this.id,
    this.requestType,
    this.responseType,
    this.description,
  });

  /// Gets the request port identifier.
  final String id;

  /// Gets the request type name.
  final String? requestType;

  /// Gets the response type name.
  final String? responseType;

  /// Gets the request port description.
  final String? description;

  /// Converts this info to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    if (requestType != null) 'requestType': requestType,
    if (responseType != null) 'responseType': responseType,
    if (description != null) 'description': description,
  };

  /// Creates request port info from JSON.
  factory RequestPortInfo.fromJson(Map<String, Object?> json) =>
      RequestPortInfo(
        id: json['id']! as String,
        requestType: json['requestType'] as String?,
        responseType: json['responseType'] as String?,
        description: json['description'] as String?,
      );
}

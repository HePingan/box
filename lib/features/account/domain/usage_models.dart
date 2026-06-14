class BoxUsageRecord {
  const BoxUsageRecord({
    required this.createdAt,
    required this.userId,
    required this.username,
    required this.model,
    required this.cost,
    required this.success,
    required this.statusCode,
    required this.errorPreview,
  });

  final DateTime createdAt;
  final String userId;
  final String username;
  final String model;
  final int cost;
  final bool success;
  final int? statusCode;
  final String errorPreview;

  factory BoxUsageRecord.fromJson(Map<String, dynamic> json) {
    final userId = json['userId']?.toString() ?? '';
    return BoxUsageRecord(
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      userId: userId,
      username: json['username']?.toString() ?? userId,
      model: json['model']?.toString() ?? '',
      cost: _asInt(json['cost']),
      success: json['success'] == true,
      statusCode: _asNullableInt(json['statusCode']),
      errorPreview: json['errorPreview']?.toString() ?? '',
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _asNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

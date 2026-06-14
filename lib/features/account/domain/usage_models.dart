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

class BoxUsageDaySummary {
  const BoxUsageDaySummary({
    required this.date,
    required this.requests,
    required this.success,
    required this.failed,
    required this.cost,
    required this.activeUsers,
  });

  final DateTime date;
  final int requests;
  final int success;
  final int failed;
  final int cost;
  final int activeUsers;

  factory BoxUsageDaySummary.empty() => BoxUsageDaySummary(
    date: DateTime.fromMillisecondsSinceEpoch(0),
    requests: 0,
    success: 0,
    failed: 0,
    cost: 0,
    activeUsers: 0,
  );

  factory BoxUsageDaySummary.fromJson(Map<String, dynamic> json) {
    return BoxUsageDaySummary(
      date:
          DateTime.tryParse(json['date']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      requests: _asInt(json['requests']),
      success: _asInt(json['success']),
      failed: _asInt(json['failed']),
      cost: _asInt(json['cost']),
      activeUsers: _asInt(json['activeUsers']),
    );
  }
}

class BoxUsageTopUserSummary {
  const BoxUsageTopUserSummary({
    required this.userId,
    required this.username,
    required this.requests,
    required this.success,
    required this.failed,
    required this.cost,
  });

  final String userId;
  final String username;
  final int requests;
  final int success;
  final int failed;
  final int cost;

  factory BoxUsageTopUserSummary.fromJson(Map<String, dynamic> json) {
    final userId = json['userId']?.toString() ?? '';
    return BoxUsageTopUserSummary(
      userId: userId,
      username: json['username']?.toString() ?? userId,
      requests: _asInt(json['requests']),
      success: _asInt(json['success']),
      failed: _asInt(json['failed']),
      cost: _asInt(json['cost']),
    );
  }
}

class BoxUsageSummary {
  const BoxUsageSummary({
    required this.today,
    required this.last7Days,
    required this.topUsersToday,
  });

  final BoxUsageDaySummary today;
  final List<BoxUsageDaySummary> last7Days;
  final List<BoxUsageTopUserSummary> topUsersToday;

  factory BoxUsageSummary.fromJson(Map<String, dynamic> json) {
    final last7Days = json['last7Days'];
    final topUsersToday = json['topUsersToday'];
    return BoxUsageSummary(
      today: json['today'] is Map
          ? BoxUsageDaySummary.fromJson(
              Map<String, dynamic>.from(json['today'] as Map),
            )
          : BoxUsageDaySummary.empty(),
      last7Days: last7Days is List
          ? last7Days
                .whereType<Map>()
                .map(
                  (item) => BoxUsageDaySummary.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
      topUsersToday: topUsersToday is List
          ? topUsersToday
                .whereType<Map>()
                .map(
                  (item) => BoxUsageTopUserSummary.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

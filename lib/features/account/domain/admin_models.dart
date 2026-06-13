class BoxAdminUserQuota {
  const BoxAdminUserQuota({
    required this.id,
    required this.username,
    required this.role,
    required this.status,
    required this.remaining,
    required this.dailyLimit,
    required this.usedToday,
    required this.totalLimit,
  });

  final String id;
  final String username;
  final String role;
  final String status;
  final int remaining;
  final int dailyLimit;
  final int usedToday;
  final int totalLimit;

  bool get isAdmin => role == 'admin';

  BoxAdminUserQuota copyWith({
    String? id,
    String? username,
    String? role,
    String? status,
    int? remaining,
    int? dailyLimit,
    int? usedToday,
    int? totalLimit,
  }) {
    return BoxAdminUserQuota(
      id: id ?? this.id,
      username: username ?? this.username,
      role: role ?? this.role,
      status: status ?? this.status,
      remaining: remaining ?? this.remaining,
      dailyLimit: dailyLimit ?? this.dailyLimit,
      usedToday: usedToday ?? this.usedToday,
      totalLimit: totalLimit ?? this.totalLimit,
    );
  }

  factory BoxAdminUserQuota.fromAdminMaps({
    required String id,
    required Map<String, dynamic> account,
    required Map<String, dynamic> quota,
  }) {
    return BoxAdminUserQuota(
      id: account['id']?.toString() ?? id,
      username: account['username']?.toString() ?? id,
      role: account['role']?.toString() ?? 'user',
      status:
          account['status']?.toString() ??
          quota['status']?.toString() ??
          'normal',
      remaining: _asInt(quota['remaining']),
      dailyLimit: _asInt(quota['dailyLimit']),
      usedToday: _asInt(quota['usedToday']),
      totalLimit: _asInt(quota['totalLimit']),
    );
  }

  factory BoxAdminUserQuota.fromFlatJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? json['userId']?.toString() ?? '';
    return BoxAdminUserQuota(
      id: id,
      username: json['username']?.toString() ?? id,
      role: json['role']?.toString() ?? 'user',
      status: json['status']?.toString() ?? 'normal',
      remaining: _asInt(json['remaining']),
      dailyLimit: _asInt(json['dailyLimit']),
      usedToday: _asInt(json['usedToday']),
      totalLimit: _asInt(json['totalLimit']),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class BoxAdminProviderConfig {
  const BoxAdminProviderConfig({
    required this.baseUrl,
    required this.apiKeyMask,
    required this.hasApiKey,
    required this.allowedModels,
    required this.updatedAt,
  });

  final String baseUrl;
  final String apiKeyMask;
  final bool hasApiKey;
  final List<String> allowedModels;
  final DateTime? updatedAt;

  factory BoxAdminProviderConfig.fromJson(Map<String, dynamic> json) {
    final rawModels = json['allowedModels'];
    final models = rawModels is List
        ? rawModels.map((item) => item.toString()).toList()
        : (rawModels?.toString() ?? '')
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList();
    return BoxAdminProviderConfig(
      baseUrl: json['baseUrl']?.toString() ?? '',
      apiKeyMask: json['apiKeyMask']?.toString() ?? '',
      hasApiKey: json['hasApiKey'] == true,
      allowedModels: models,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}

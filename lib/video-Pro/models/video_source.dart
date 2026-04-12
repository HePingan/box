class VideoSource {
  final String id;
  final String name;
  final String url;
  final String detailUrl;
  final bool isEnabled;

  /// 是否隐藏
  final bool isHidden;

  /// 隐藏原因：
  /// - ''      ：未隐藏
  /// - 'manual'：手动隐藏
  /// - 'auto'  ：自动隐藏
  final String hiddenReason;

  /// 连续失败次数
  final int failCount;

  /// 最近一次失败时间
  final DateTime? lastFailAt;

  /// 隐藏时间
  final DateTime? hiddenAt;

  const VideoSource({
    required this.id,
    required this.name,
    required this.url,
    required this.detailUrl,
    this.isEnabled = true,
    this.isHidden = false,
    this.hiddenReason = '',
    this.failCount = 0,
    this.lastFailAt,
    this.hiddenAt,
  });

  /// 当前是否可用（启用且未隐藏）
  bool get isAvailable => isEnabled && !isHidden;

  VideoSource copyWith({
    String? id,
    String? name,
    String? url,
    String? detailUrl,
    bool? isEnabled,
    bool? isHidden,
    String? hiddenReason,
    int? failCount,
    DateTime? lastFailAt,
    DateTime? hiddenAt,
  }) {
    return VideoSource(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      detailUrl: detailUrl ?? this.detailUrl,
      isEnabled: isEnabled ?? this.isEnabled,
      isHidden: isHidden ?? this.isHidden,
      hiddenReason: hiddenReason ?? this.hiddenReason,
      failCount: failCount ?? this.failCount,
      lastFailAt: lastFailAt ?? this.lastFailAt,
      hiddenAt: hiddenAt ?? this.hiddenAt,
    );
  }

  factory VideoSource.fromJson(Map<String, dynamic> json) {
    String asString(dynamic value, [String fallback = '']) {
      if (value == null) return fallback;
      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
      return text;
    }

    bool asBool(dynamic value, [bool fallback = true]) {
      if (value is bool) return value;

      final text = value?.toString().trim().toLowerCase();
      if (text == null || text.isEmpty) return fallback;

      if (['1', 'true', 'yes', 'y', 'on'].contains(text)) return true;
      if (['0', 'false', 'no', 'n', 'off'].contains(text)) return false;

      return fallback;
    }

    int asInt(dynamic value, [int fallback = 0]) {
      if (value == null) return fallback;
      if (value is int) return value;
      return int.tryParse(value.toString().trim()) ?? fallback;
    }

    DateTime? asDateTime(dynamic value) {
      if (value == null) return null;

      if (value is DateTime) return value;

      if (value is int) {
        if (value <= 0) return null;
        return DateTime.fromMillisecondsSinceEpoch(value);
      }

      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') return null;

      final ms = int.tryParse(text);
      if (ms != null && ms > 0) {
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }

      try {
        return DateTime.parse(text);
      } catch (_) {
        return null;
      }
    }

    final url = asString(
      json['url'] ??
          json['listUrl'] ??
          json['list_url'] ??
          json['apiUrl'] ??
          json['api_url'],
    );

    final detailUrl = asString(
      json['detailUrl'] ??
          json['detail_url'] ??
          json['detail'] ??
          json['apiDetail'] ??
          json['api_detail'] ??
          url,
      url,
    );

    return VideoSource(
      id: asString(json['id'] ?? json['sourceId'] ?? json['sid'] ?? url),
      name: asString(
        json['name'] ?? json['sourceName'] ?? json['title'],
        '未知源',
      ),
      url: url,
      detailUrl: detailUrl,
      isEnabled: asBool(
        json['isEnabled'] ?? json['enabled'] ?? json['status'] ?? true,
      ),
      isHidden: asBool(json['isHidden'] ?? json['hidden'] ?? false, false),
      hiddenReason: asString(
        json['hiddenReason'] ?? json['hideReason'] ?? '',
        '',
      ),
      failCount: asInt(json['failCount'] ?? json['fails'] ?? 0, 0),
      lastFailAt: asDateTime(json['lastFailAt'] ?? json['last_fail_at']),
      hiddenAt: asDateTime(json['hiddenAt'] ?? json['hidden_at']),
    );
  }

  /// 适用于把“本地保存的状态”叠加到基础源数据上
  factory VideoSource.fromStateJson(
    VideoSource base,
    Map<String, dynamic> state,
  ) {
    bool asBool(dynamic value, [bool fallback = false]) {
      if (value is bool) return value;
      final text = value?.toString().trim().toLowerCase();
      if (text == null || text.isEmpty) return fallback;
      if (['1', 'true', 'yes', 'y', 'on'].contains(text)) return true;
      if (['0', 'false', 'no', 'n', 'off'].contains(text)) return false;
      return fallback;
    }

    int asInt(dynamic value, [int fallback = 0]) {
      if (value == null) return fallback;
      if (value is int) return value;
      return int.tryParse(value.toString().trim()) ?? fallback;
    }

    DateTime? asDateTime(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;

      if (value is int) {
        if (value <= 0) return null;
        return DateTime.fromMillisecondsSinceEpoch(value);
      }

      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') return null;

      final ms = int.tryParse(text);
      if (ms != null && ms > 0) {
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }

      try {
        return DateTime.parse(text);
      } catch (_) {
        return null;
      }
    }

    return base.copyWith(
      isHidden: asBool(state['isHidden'] ?? state['hidden'], base.isHidden),
      hiddenReason: state['hiddenReason']?.toString() ??
          state['hideReason']?.toString() ??
          base.hiddenReason,
      failCount: asInt(state['failCount'] ?? state['fails'], base.failCount),
      lastFailAt: asDateTime(state['lastFailAt'] ?? state['last_fail_at']) ??
          base.lastFailAt,
      hiddenAt: asDateTime(state['hiddenAt'] ?? state['hidden_at']) ??
          base.hiddenAt,
      isEnabled: state.containsKey('isEnabled')
          ? asBool(state['isEnabled'], base.isEnabled)
          : base.isEnabled,
    );
  }

  /// 完整 JSON：适合网络/配置导入导出
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'detailUrl': detailUrl,
        'isEnabled': isEnabled,
        'isHidden': isHidden,
        'hiddenReason': hiddenReason,
        'failCount': failCount,
        'lastFailAt': lastFailAt?.millisecondsSinceEpoch,
        'hiddenAt': hiddenAt?.millisecondsSinceEpoch,
      };

  /// 仅保存“状态”的 JSON：适合本地持久化
  Map<String, dynamic> toStateJson() => {
        'isHidden': isHidden,
        'hiddenReason': hiddenReason,
        'failCount': failCount,
        'lastFailAt': lastFailAt?.millisecondsSinceEpoch,
        'hiddenAt': hiddenAt?.millisecondsSinceEpoch,
        'isEnabled': isEnabled,
      };
}
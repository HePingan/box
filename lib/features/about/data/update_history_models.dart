/// 历史版本更新日志的数据模型。
///
/// 对应服务端 `GET /api/v1/app-updates/history`，刻意**不含**下载地址与
/// sha256：历史版本里存在验签坏掉的包（v1.9.9+199）和被归档的记录，把下载
/// 地址带到客户端等于给用户一条装到坏版本的路。要装新版走「检查更新」那条
/// 带验签的正规链路。
class UpdateHistoryEntry {
  const UpdateHistoryEntry({
    required this.versionName,
    required this.versionCode,
    required this.changelog,
    this.title,
    this.publishedAt,
    this.forceUpdate = false,
  });

  final String versionName;
  final int versionCode;
  final List<String> changelog;
  final String? title;
  final DateTime? publishedAt;
  final bool forceUpdate;

  factory UpdateHistoryEntry.fromJson(Map<String, dynamic> json) {
    return UpdateHistoryEntry(
      versionName: (json['versionName'] as String?)?.trim() ?? '',
      versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
      // changelog 服务端存的是 JSON 数组，但历史记录里有单条长文本内含换行的
      // 情况（1.10.2 就是一整段）。这里不拆行，交给 UI 决定怎么排版。
      changelog: (json['changelog'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(growable: false),
      title: (json['title'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['title'] as String).trim(),
      publishedAt: _parseDate(json['publishedAt']),
      forceUpdate: json['forceUpdate'] == true,
    );
  }

  /// 服务端给的是 ISO8601 带时区。解析失败返回 null 而不是抛 —— 一条记录的
  /// 时间戳坏了不该让整页历史打不开。
  static DateTime? _parseDate(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  /// 「2026-09-05」这种给人看的短日期。没有时间戳时返回 null，UI 自行省略。
  String? get publishedDateLabel {
    final at = publishedAt;
    if (at == null) return null;
    final m = at.month.toString().padLeft(2, '0');
    final d = at.day.toString().padLeft(2, '0');
    return '${at.year}-$m-$d';
  }

  /// 展示用标题：有 title 用 title，否则退回版本号。
  String get displayTitle {
    final t = title;
    if (t != null && t.isNotEmpty) return t;
    return 'v$versionName';
  }
}

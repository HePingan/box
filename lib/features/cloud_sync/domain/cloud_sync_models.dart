/// 云端书源 / 公告的客户端模型。
///
/// 对应服务端 `GET /api/book-sources` 与 `GET /api/announcements`。
library;

/// 云端下发的单条书源。
///
/// [removed] 为墓碑标记：服务端删除书源时不物理删除，而是下发 removed=true，
/// 客户端据此删掉本地对应条目。墓碑条目只带 [id]，其余字段为空。
class CloudBookSourceEntry {
  const CloudBookSourceEntry({
    required this.id,
    required this.name,
    required this.url,
    required this.group,
    required this.rawJson,
    required this.enabled,
    required this.weight,
    required this.sort,
    required this.updatedAt,
    required this.removed,
  });

  factory CloudBookSourceEntry.fromJson(Map<String, dynamic> json) {
    return CloudBookSourceEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      group: json['group']?.toString() ?? '',
      rawJson: json['rawJson']?.toString() ?? '',
      enabled: json['enabled'] != false,
      weight: _asInt(json['weight']),
      sort: _asInt(json['sort']),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      removed: json['removed'] == true,
    );
  }

  final String id;
  final String name;
  final String url;
  final String group;
  final String rawJson;
  final bool enabled;
  final int weight;
  final int sort;
  final DateTime? updatedAt;
  final bool removed;
}

/// `GET /api/book-sources` 的响应。
///
/// [changed] 为 false 时服务端不下发 [sources]（客户端已是最新版本）。
class CloudBookSourceBundle {
  const CloudBookSourceBundle({
    required this.version,
    required this.changed,
    required this.count,
    required this.publishedAt,
    required this.sources,
  });

  factory CloudBookSourceBundle.fromJson(Map<String, dynamic> json) {
    final raw = json['sources'];
    return CloudBookSourceBundle(
      version: _asInt(json['version']),
      changed: json['changed'] != false,
      count: _asInt(json['count']),
      publishedAt: DateTime.tryParse(json['publishedAt']?.toString() ?? ''),
      sources: raw is List
          ? raw
              .whereType<Map>()
              .map(
                (e) => CloudBookSourceEntry.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList(growable: false)
          : const <CloudBookSourceEntry>[],
    );
  }

  final int version;
  final bool changed;
  final int count;
  final DateTime? publishedAt;
  final List<CloudBookSourceEntry> sources;
}

/// 一条站内公告。
class AnnouncementEntry {
  const AnnouncementEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.level,
    required this.publishedAt,
    required this.pinned,
    required this.linkUrl,
  });

  factory AnnouncementEntry.fromJson(Map<String, dynamic> json) {
    return AnnouncementEntry(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      level: _normalizeLevel(json['level']?.toString()),
      publishedAt:
          DateTime.tryParse(json['publishedAt']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
      pinned: json['pinned'] == true,
      linkUrl: json['linkUrl']?.toString() ?? '',
    );
  }

  final String id;
  final String title;
  final String body;

  /// info / notice / warning
  final String level;
  final DateTime publishedAt;
  final bool pinned;
  final String linkUrl;

  static String _normalizeLevel(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    return const {'info', 'notice', 'warning'}.contains(value) ? value : 'info';
  }
}

/// 书源同步结果，用于给用户一句可读的反馈。
class BookSourceSyncResult {
  const BookSourceSyncResult({
    required this.version,
    required this.added,
    required this.updated,
    required this.removed,
    required this.skipped,
    required this.upToDate,
  });

  const BookSourceSyncResult.upToDateAt(this.version)
      : added = 0,
        updated = 0,
        removed = 0,
        skipped = 0,
        upToDate = true;

  final int version;
  final int added;
  final int updated;
  final int removed;

  /// 云端条目缺 rawJson / 解析失败而跳过的数量。
  final int skipped;
  final bool upToDate;

  bool get hasChanges => added > 0 || updated > 0 || removed > 0;

  String get summary {
    if (upToDate) return '书源已是最新（v$version）';
    if (!hasChanges) return '书源无变化（v$version）';
    final parts = <String>[];
    if (added > 0) parts.add('新增 $added');
    if (updated > 0) parts.add('更新 $updated');
    if (removed > 0) parts.add('移除 $removed');
    final tail = skipped > 0 ? '，跳过 $skipped 条无效数据' : '';
    return '${parts.join('、')} 个书源$tail（v$version）';
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('${value ?? ''}') ?? 0;
}

// lib/features/home/data/ai_hot_models.dart
//
// AI HOT（aihot.virxact.com）公开条目的数据模型。
//
// 字段以实测响应为准（2026-09-01 抓取 /api/public/items?mode=selected）：
//   id, title, title_en, url, permalink, source, publishedAt,
//   discoveredAt, summary, category, score, selected, attribution{source,canonical}
//
// 解析原则：只有 id/title 是硬要求，其余字段一律容错。上游加字段、改类型
// （int 变 double、缺 summary）都不能让整批条目丢失——这是 A4 那次汇率
// 裸 `as num` 崩溃留下的教训，凡外部 JSON 一律逐字段判型。
library;

/// 单条 AI 热点。
class AiHotItem {
  const AiHotItem({
    required this.id,
    required this.title,
    this.url,
    this.permalink,
    this.source,
    this.summary,
    this.category,
    this.publishedAt,
    this.score,
  });

  final String id;
  final String title;

  /// 原文链接（可能是 x.com / 论文站等站外地址）。
  final String? url;

  /// AI HOT 站内详情页。署名要求指向这里，不是 [url]。
  final String? permalink;

  final String? source;
  final String? summary;
  final String? category;
  final DateTime? publishedAt;
  final int? score;

  /// 点开时优先用站内 permalink（可控、可信、带署名），
  /// 没有再退回原文 url。两者都空则不可点。
  String? get openUrl {
    final p = permalink?.trim();
    if (p != null && p.isNotEmpty) return p;
    final u = url?.trim();
    if (u != null && u.isNotEmpty) return u;
    return null;
  }

  /// 分类的中文显示名。未知分类回显原值，不硬编码成「其它」——
  /// 上游新增分类时用户至少还能看到真实标签。
  String get categoryLabel {
    switch (category) {
      case 'paper':
        return '论文';
      case 'ai-models':
        return '模型';
      case 'product':
        return '产品';
      case 'funding':
        return '融资';
      case 'policy':
        return '政策';
      case 'research':
        return '研究';
      case 'tool':
        return '工具';
      case 'opinion':
        return '观点';
      case null:
        return '';
      default:
        return category!;
    }
  }

  /// 相对时间（「3 小时前」）。没有发布时间就返回 null，让 UI 不占位。
  ///
  /// 故意不用 intl：首页只要粗粒度，精确到分钟没意义，
  /// 而且上游 publishedAt 本身就有分钟级抖动。
  String? get relativeTime {
    final at = publishedAt;
    if (at == null) return null;
    final diff = DateTime.now().difference(at);
    if (diff.isNegative) return '刚刚';
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${at.month}-${at.day.toString().padLeft(2, '0')}';
  }

  static String? _str(dynamic v) {
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    return null;
  }

  static int? _int(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static DateTime? _date(dynamic v) {
    if (v is! String) return null;
    return DateTime.tryParse(v.trim())?.toLocal();
  }

  /// 从单个 JSON 对象解析。id/title 缺失或为空返回 null（调用方跳过该条）。
  static AiHotItem? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);

    final id = _str(map['id']);
    final title = _str(map['title']);
    if (id == null || title == null) return null;

    return AiHotItem(
      id: id,
      title: title,
      url: _str(map['url']),
      permalink: _str(map['permalink']),
      source: _str(map['source']),
      summary: _str(map['summary']),
      category: _str(map['category']),
      publishedAt: _date(map['publishedAt']),
      score: _int(map['score']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    if (url != null) 'url': url,
    if (permalink != null) 'permalink': permalink,
    if (source != null) 'source': source,
    if (summary != null) 'summary': summary,
    if (category != null) 'category': category,
    if (publishedAt != null) 'publishedAt': publishedAt!.toUtc().toIso8601String(),
    if (score != null) 'score': score,
  };
}

/// 一批热点 + 署名信息。
class AiHotFeed {
  const AiHotFeed({
    required this.items,
    this.attributionSource,
    this.attributionCanonical,
    this.fromCache = false,
  });

  const AiHotFeed.empty()
    : items = const <AiHotItem>[],
      attributionSource = null,
      attributionCanonical = null,
      fromCache = false;

  final List<AiHotItem> items;

  /// 上游要求的署名名称（实测为 'AIHOT'）。
  final String? attributionSource;
  final String? attributionCanonical;

  /// 这批数据是否来自本地缓存（网络失败降级时为 true）。
  /// UI 用它决定要不要提示「离线内容」。
  final bool fromCache;

  bool get isEmpty => items.isEmpty;

  /// 展示用署名文案。上游没给就回落到固定的 AI HOT，
  /// 保证署名永远存在——这是使用别人数据的底线。
  String get attributionLabel => attributionSource ?? 'AI HOT';

  AiHotFeed copyWith({bool? fromCache}) => AiHotFeed(
    items: items,
    attributionSource: attributionSource,
    attributionCanonical: attributionCanonical,
    fromCache: fromCache ?? this.fromCache,
  );

  /// 解析 `/api/public/items` 响应体。
  ///
  /// 单条坏数据只跳过那一条，不让整批失败。
  static AiHotFeed fromJson(dynamic decoded) {
    if (decoded is! Map) return const AiHotFeed.empty();
    final map = Map<String, dynamic>.from(decoded);

    final rawItems = map['items'];
    final items = <AiHotItem>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        final item = AiHotItem.tryParse(entry);
        if (item != null) items.add(item);
      }
    }

    // 署名挂在每条 item 上，取第一条有 attribution 的即可。
    String? attrSource;
    String? attrCanonical;
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map && entry['attribution'] is Map) {
          final attr = Map<String, dynamic>.from(
            entry['attribution'] as Map,
          );
          attrSource ??= AiHotItem._str(attr['source']);
          attrCanonical ??= AiHotItem._str(attr['canonical']);
          if (attrSource != null) break;
        }
      }
    }

    return AiHotFeed(
      items: items,
      attributionSource: attrSource,
      attributionCanonical: attrCanonical,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'items': items.map((e) => e.toJson()).toList(),
    if (attributionSource != null) 'attributionSource': attributionSource,
    if (attributionCanonical != null) 'attributionCanonical': attributionCanonical,
  };

  /// 从本地缓存快照还原（结构与 [toJson] 对应，非 API 原始结构）。
  static AiHotFeed fromCacheJson(dynamic decoded) {
    if (decoded is! Map) return const AiHotFeed.empty();
    final map = Map<String, dynamic>.from(decoded);
    final rawItems = map['items'];
    final items = <AiHotItem>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        final item = AiHotItem.tryParse(entry);
        if (item != null) items.add(item);
      }
    }
    return AiHotFeed(
      items: items,
      attributionSource: AiHotItem._str(map['attributionSource']),
      attributionCanonical: AiHotItem._str(map['attributionCanonical']),
      fromCache: true,
    );
  }
}

// lib/features/home/data/ai_hot_models.dart
//
// AI HOT（aihot.news）公开条目的数据模型。
//
// 字段以实测响应为准（2026-10-02 抓取 https://aihot.news/api/v1/items?mode=selected&window=7d）：
//   id, title, originalTitle, summary, source{name}, links{aihot,original},
//   publishedAt, discoveredAt, category, score, selected, reason,
//   attribution{name,url}
//
// 上游 2.0 把接口从 /api/public/* 搬到 /api/v1（旧接口 2026-10-31 停用），
// 字段路径同时改了一批。两边都读，是为了让**老版本写进本机缓存的快照**还能显示：
//   url        → links.original
//   permalink  → links.aihot
//   source     → source.name
//   title_en   → originalTitle
//   attribution{source,canonical} → attribution{name,url}
// 顶层 count/hasNext/nextCursor → page.count/page.hasMore/page.nextCursor（首页不用分页，未读）
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
  ///
  /// 映射必须覆盖**上游实际在用的分类**，否则中文界面上会直接出现英文 slug。
  /// 2026-10-02 拉 50 条精选实测的分布是：
  ///   ai-products 13 / tip 11 / ai-models 11 / industry 10 / paper 5
  /// 而当时的映射只认 paper、ai-models（另有 product/funding/policy/research/tool/opinion
  /// 这些**旧接口**的取值）—— 于是最常出现的三类全部落到 default，行上写着
  /// `ai-products`、`tip`、`industry`。
  ///
  /// 中文名照抄上游自己的说法（`https://aihot.news/api/v1/agent`：
  /// 「category=ai-models（模型）、ai-products（产品）、industry（行业）、paper（论文）
  /// 或 tip（教程与观点）」），不要自己另起名字。
  /// `test/features/home/ai_hot_feed_test.dart` 里有一条夹具驱动的用例：
  /// 快照中出现过的分类都必须有中文标签 —— 换夹具（tool/refresh_ai_hot_fixture.py）
  /// 时若上游加了新分类，用例会当场红，提示补这一档。
  String get categoryLabel {
    switch (category) {
      case 'paper':
        return '论文';
      case 'ai-models':
        return '模型';
      // 现役取值（v1）。legacy 的 product 也留一份，老缓存里是它。
      case 'ai-products':
      case 'product':
        return '产品';
      case 'industry':
        return '行业';
      case 'tip':
        return '教程';
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
  ///
  /// 同时吃 v1 与旧接口两种字段路径（见文件头的对照表）。
  static AiHotItem? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);

    final id = _str(map['id']);
    final title = _str(map['title']);
    if (id == null || title == null) return null;

    // v1：links{aihot,original}；旧：permalink / url。
    final links = map['links'] is Map
        ? Map<String, dynamic>.from(map['links'] as Map)
        : const <String, dynamic>{};
    // v1：source.name；旧：source 直接是字符串。
    final sourceRaw = map['source'];
    final sourceName = sourceRaw is Map
        ? _str(Map<String, dynamic>.from(sourceRaw)['name'])
        : _str(sourceRaw);

    return AiHotItem(
      id: id,
      title: title,
      url: _str(links['original']) ?? _str(map['url']),
      permalink: _str(links['aihot']) ?? _str(map['permalink']),
      source: sourceName,
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
    this.fromCache = false,
  });

  const AiHotFeed.empty()
    : items = const <AiHotItem>[],
      attributionSource = null,
      fromCache = false;

  final List<AiHotItem> items;

  /// 上游要求的署名名称（v1 在 attribution.name，旧接口在 attribution.source，实测 'AIHOT'）。
  ///
  /// 只保留名称：署名要求回链的是**每一条自己的站内页**（item.permalink），
  /// v1 的 attribution.url 与 links.aihot 是同一个地址，所以这里没有「站点级 canonical」
  /// 这种东西。曾经按站点 canonical 用过一次，结果是「更多」打开的是第一条热点本身。
  final String? attributionSource;

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
    fromCache: fromCache ?? this.fromCache,
  );

  /// 解析 `/api/v1/items`（或旧 `/api/public/items`）响应体。
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
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map && entry['attribution'] is Map) {
          final attr = Map<String, dynamic>.from(
            entry['attribution'] as Map,
          );
          // v1 是 name，旧接口是 source。
          attrSource ??= AiHotItem._str(attr['name']) ??
              AiHotItem._str(attr['source']);
          if (attrSource != null) break;
        }
      }
    }

    return AiHotFeed(items: items, attributionSource: attrSource);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'items': items.map((e) => e.toJson()).toList(),
    if (attributionSource != null) 'attributionSource': attributionSource,
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
      fromCache: true,
    );
  }
}

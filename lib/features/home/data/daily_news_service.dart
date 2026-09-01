// lib/features/home/data/daily_news_service.dart
//
// 今日热闻（知乎日报公开接口）的客户端。
//
// 这段逻辑原先内联在 HomePage._fetchDailyNews 里，有四个实际问题：
//   1. 两个端点用 Future.wait 并发，任一抛异常整个 await 就抛 —— 另一个
//      已经成功拿到的数据被一起丢掉，UI 显示「网络异常」。
//   2. 结果 shuffle() 后再 take(3)，每次下拉刷新顺序全变，用户刚看到的
//      标题下一秒就找不到了。
//   3. 没有缓存，每次重建首页都打网络；离线时热闻区直接空白。
//   4. 失败文案被塞成一条列表项（isPlaceholder: true），数据与错误态混在
//      同一个列表里，调用方得靠布尔标志反推这条到底能不能点。
//
// 抽出来后：部分成功照用、排序稳定、5 分钟缓存 + 离线降级、
// 错误态挂在 feed 上而不是伪装成条目。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:box/core/storage/cache_store.dart';

/// 一条热闻。
@immutable
class DailyNewsItem {
  const DailyNewsItem({required this.title, this.url});

  final String title;

  /// 详情页地址。上游偶尔给不出，此时这条不可点。
  final String? url;

  bool get isOpenable => url != null && url!.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{'title': title, 'url': url};

  static DailyNewsItem? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final title = raw['title'];
    if (title is! String || title.isEmpty) return null;
    final url = raw['url'];
    return DailyNewsItem(title: title, url: url is String ? url : null);
  }

  @override
  bool operator ==(Object other) =>
      other is DailyNewsItem && other.title == title && other.url == url;

  @override
  int get hashCode => Object.hash(title, url);
}

/// 一次拉取的结果。
///
/// 关键设计：`items` 只装真新闻，错误信息走 [errorMessage]。这样 UI 不必
/// 再问「这条是不是提示文案」——列表非空就全都是可展示的内容。
@immutable
class DailyNewsFeed {
  const DailyNewsFeed({
    required this.items,
    this.errorMessage = '',
    this.fromCache = false,
  });

  const DailyNewsFeed.empty()
      : items = const <DailyNewsItem>[],
        errorMessage = '',
        fromCache = false;

  final List<DailyNewsItem> items;

  /// 拿不到任何可展示内容时的提示文案；成功时为空串。
  final String errorMessage;

  /// 内容来自缓存（可能已过期）。
  final bool fromCache;

  bool get hasError => errorMessage.isNotEmpty;
  bool get isEmpty => items.isEmpty;
}

/// 单个 GET 的注入点。
///
/// 用函数而不是 http.Client：这里要按 uri 分别决定桩行为（今日成功、
/// 昨日失败），MockClient 也能做但每个测试都要写一遍分发逻辑。
typedef DailyNewsGet = Future<http.Response> Function(Uri uri);

class DailyNewsService {
  DailyNewsService({CacheStore? cache, DailyNewsGet? get})
      : _cache = cache ?? CacheStore(namespace: 'daily_news'),
        _get = get ?? _defaultGet;

  final CacheStore _cache;
  final DailyNewsGet _get;

  static const String _host = 'news-at.zhihu.com';
  static const String _latestPath = '/api/4/news/latest';
  static const String _beforePath = '/api/4/news/before';

  static const String _cacheKey = 'daily_news_v1';

  /// 无 TTL 的镜像键。CacheStore.read 过期会自己删掉并返回 null，
  /// 所以「已过期但仍可降级用」的副本必须单独存一份。
  static const String _staleKey = 'daily_news_stale_v1';

  /// 与 AI HOT 区块同量级。热闻是首页次要内容，5 分钟内重复请求没意义。
  static const Duration cacheTtl = Duration(minutes: 5);

  /// 单个端点的超时。两个端点并发，总耗时约等于这个值。
  static const Duration timeout = Duration(seconds: 10);

  /// 首页预览条数。
  static const int previewCount = 3;

  static Future<http.Response> _defaultGet(Uri uri) {
    return http
        .get(uri, headers: const <String, String>{'Accept': 'application/json'})
        .timeout(timeout);
  }

  /// 拉取热闻。
  ///
  /// 顺序：未过期缓存 → 网络（今日 + 昨日，部分成功照用）→ 过期缓存降级。
  /// 任何一步都不抛异常给 UI。
  Future<DailyNewsFeed> fetch({
    int take = previewCount,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await _readCache(allowExpired: false);
      if (cached != null && cached.items.isNotEmpty) {
        return DailyNewsFeed(
          items: _trim(cached.items, take),
          fromCache: true,
        );
      }
    }

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final stamp = '${yesterday.year}'
        '${yesterday.month.toString().padLeft(2, '0')}'
        '${yesterday.day.toString().padLeft(2, '0')}';

    // 每个请求自己 try/catch 再收敛，而不是让 Future.wait 整体抛。
    // 这是「部分成功不丢数据」的关键：一个端点挂掉不影响另一个。
    final fetched = await Future.wait(<Future<List<DailyNewsItem>>>[
      _fetchOne(Uri.https(_host, _latestPath)),
      _fetchOne(Uri.https(_host, '$_beforePath/$stamp')),
    ]);

    // 今日在前、昨日在后，且各端点内部保持上游给的原序。
    // 不做 shuffle：随机排序会让用户每次下拉都丢失阅读位置。
    final merged = <DailyNewsItem>[];
    final seen = <String>{};
    for (final batch in fetched) {
      for (final item in batch) {
        // 两个端点在跨日边界会返回同一条，按 title+url 去重。
        final key = '${item.title}\u0000${item.url ?? ''}';
        if (!seen.add(key)) continue;
        merged.add(item);
      }
    }

    if (merged.isNotEmpty) {
      await _writeCache(merged);
      return DailyNewsFeed(items: _trim(merged, take));
    }

    // 网络一无所获：退回缓存（允许过期），有旧内容也比空白好。
    final stale = await _readCache(allowExpired: true);
    if (stale != null && stale.items.isNotEmpty) {
      return DailyNewsFeed(items: _trim(stale.items, take), fromCache: true);
    }

    return const DailyNewsFeed(
      items: <DailyNewsItem>[],
      errorMessage: '网络异常，请下拉刷新重试',
    );
  }

  /// 拉一个端点。失败返回空列表，不抛。
  Future<List<DailyNewsItem>> _fetchOne(Uri uri) async {
    try {
      final resp = await _get(uri);
      if (resp.statusCode != 200) return const <DailyNewsItem>[];
      return _parse(resp.bodyBytes);
    } catch (_) {
      return const <DailyNewsItem>[];
    }
  }

  /// 解析 stories 数组。
  ///
  /// 走 bodyBytes + utf8.decode 而不是 resp.body：上游不带 charset 时
  /// http 包会按 latin1 解，中文标题直接变乱码。
  List<DailyNewsItem> _parse(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return const <DailyNewsItem>[];
      final stories = decoded['stories'];
      if (stories is! List) return const <DailyNewsItem>[];

      final out = <DailyNewsItem>[];
      for (final raw in stories) {
        final item = DailyNewsItem.fromJson(raw);
        if (item != null) out.add(item);
      }
      return out;
    } catch (_) {
      return const <DailyNewsItem>[];
    }
  }

  List<DailyNewsItem> _trim(List<DailyNewsItem> items, int take) {
    final limit = take.clamp(1, 50);
    return items.length <= limit ? items : items.sublist(0, limit);
  }

  Future<DailyNewsFeed?> _readCache({required bool allowExpired}) async {
    try {
      final raw =
          await _cache.read(allowExpired ? _staleKey : _cacheKey);
      if (raw == null) return null;
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! List) return null;

      final items = <DailyNewsItem>[];
      for (final entry in decoded) {
        final item = DailyNewsItem.fromJson(entry);
        if (item != null) items.add(item);
      }
      return items.isEmpty ? null : DailyNewsFeed(items: items, fromCache: true);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(List<DailyNewsItem> items) async {
    try {
      // 存合并后的全量而不是裁剪后的 take 条：调用方改 take 时缓存仍然够用。
      final payload = jsonEncode(items.map((e) => e.toJson()).toList());
      await _cache.write(_cacheKey, payload, ttl: cacheTtl);
      await _cache.write(_staleKey, payload);
    } catch (_) {
      // 缓存写失败不影响本次展示。
    }
  }

  @visibleForTesting
  Future<void> clearCacheForTesting() async {
    await _cache.remove(_cacheKey);
    await _cache.remove(_staleKey);
  }
}

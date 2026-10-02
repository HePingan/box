// lib/features/home/data/ai_hot_service.dart
//
// AI HOT 公开只读接口的客户端。
//
// 2026-10-02 迁移到 v1（上游公告：旧接口 /api/public/* 与旧域名 aihot.virxact.com
// 于 2026-10-31 一起停用，之后旧域名只做跳转 —— 公告原文在
// https://aihot.news/agent?tab=api 的「旧接口和旧域名」一节）：
//   - 主机 aihot.virxact.com → aihot.news（**条目页也在 aihot.news**，
//     这正是「点开一条热点看到视界日报门户页」那个 bug 的根因，见 daily_news_url_policy.dart）
//   - 路径 /api/public/items → /api/v1/items
//   - 参数 take → limit（v1 只认 OpenAPI 里声明过的参数，带未知参数直接 400，
//     所以旧名不能留着做兼容）
//   - 新增 window（只认 24h / 7d 这类枚举；不传 = 服务端默认）。这里显式给 7d，
//     与旧接口的默认窗口对齐，首页的条数/新鲜度不会因为迁移而变。
//
// 上游约束（实测）：
//   - 匿名只读，不需要 key；同一 IP 每分钟约 60 次以上返回 429（客户端 5 分钟缓存足够）
//   - 建议开压缩 + 带 If-None-Match（304 表示没变化）。压缩 dart:io 的 HttpClient
//     默认已开（autoUncompress）。ETag 没做：5 分钟客户端缓存已经把它压到 12 次/小时，
//     离限流很远，收益不值得多一份需要持久化的状态。
//   - 使用其数据必须署名 AI HOT 并可回链站内条目页
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/home/data/ai_hot_models.dart';

class AiHotService {
  AiHotService({http.Client? client, CacheStore? cache})
    : _client = client ?? http.Client(),
      _cache = cache ?? CacheStore(namespace: 'ai_hot');

  final http.Client _client;
  final CacheStore _cache;

  /// 接口主机。注意与条目页主机是同一个（aihot.news），但不是旧域名。
  static const String _host = 'aihot.news';

  /// AI HOT 站点首页（「更多」的落点：站内条目列表）。
  ///
  /// 不用「第一条的 canonical」当站点地址 —— 那是**单条**条目页，
  /// 用它做「更多」会点开第一条热点本身（曾经就是这样）。
  static const String siteUrl = 'https://aihot.news/';
  static const String _itemsPath = '/api/v1/items';

  /// 时间窗：只认 24h / 7d 这类枚举值（实测 1h/6h/30d 都返回 400）。
  /// 取 7d 是为了与旧接口的默认窗口对齐。
  static const String _window = '7d';

  static const String _cacheKey = 'selected_feed_v1';

  /// 与服务端缓存同量级。上游 items 端点本身有 5 分钟缓存，
  /// 客户端再存 5 分钟不会看到更旧的数据，但能挡掉页面反复重建时的重复请求。
  static const Duration cacheTtl = Duration(minutes: 5);

  /// 网络超时。首页是次要区块，不该让用户为它等太久。
  static const Duration timeout = Duration(seconds: 8);

  /// 首页预览条数上限。
  static const int previewCount = 4;

  /// 拉取精选热点。
  ///
  /// 顺序：内存/磁盘缓存未过期 → 直接返回；否则请求网络；
  /// 网络失败时回落到「已过期但仍存在」的缓存（标记 fromCache），
  /// 都没有才返回空。任何一步都不抛异常给 UI。
  Future<AiHotFeed> fetchSelected({
    int take = previewCount,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await _readCache(allowExpired: false);
      if (cached != null && cached.items.isNotEmpty) return cached;
    }

    try {
      final uri = Uri.https(_host, _itemsPath, <String, String>{
        'mode': 'selected',
        'window': _window,
        // v1 的参数名是 limit（旧接口的 take 会直接 400）。
        'limit': '${take.clamp(1, 50)}',
      });

      final resp = await _client
          .get(uri, headers: const <String, String>{'Accept': 'application/json'})
          .timeout(timeout);

      if (resp.statusCode != 200) {
        return await _fallback();
      }

      final feed = AiHotFeed.fromJson(jsonDecode(resp.body));
      if (feed.isEmpty) return await _fallback();

      await _writeCache(feed);
      return feed;
    } catch (_) {
      // 网络异常/超时/JSON 损坏一律降级到缓存，不把异常冒给首页。
      return await _fallback();
    }
  }

  /// 网络路径失败后的兜底：允许返回已过期的缓存。
  Future<AiHotFeed> _fallback() async {
    final stale = await _readCache(allowExpired: true);
    if (stale != null && stale.items.isNotEmpty) return stale;
    return const AiHotFeed.empty();
  }

  Future<AiHotFeed?> _readCache({required bool allowExpired}) async {
    try {
      // CacheStore.read 到期会自己删除并返回 null，所以「允许过期」
      // 需要走独立的镜像键：主键带 TTL，镜像键不带。
      final raw = allowExpired
          ? await _cache.read(_staleKey)
          : await _cache.read(_cacheKey);
      if (raw == null) return null;
      final decoded = raw is String ? jsonDecode(raw) : raw;
      final feed = AiHotFeed.fromCacheJson(decoded);
      return feed.items.isEmpty ? null : feed;
    } catch (_) {
      return null;
    }
  }

  static const String _staleKey = 'selected_feed_stale_v1';

  Future<void> _writeCache(AiHotFeed feed) async {
    try {
      final payload = jsonEncode(feed.toJson());
      await _cache.write(_cacheKey, payload, ttl: cacheTtl);
      // 无 TTL 的镜像：网络长时间不可用时还能拿出上次的内容，
      // 比首页空着好。UI 会标注这是离线内容。
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

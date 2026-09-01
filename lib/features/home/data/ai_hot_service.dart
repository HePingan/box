// lib/features/home/data/ai_hot_service.dart
//
// AI HOT 公开只读接口的客户端。
//
// 上游约束（来自接口文档实测）：
//   - 限流 600 req/min/IP，且服务端已有 5 分钟缓存 → 客户端不做高频轮询
//   - 默认走 mode=selected（每日精选），不用 mode=all（量大且杂）
//   - 使用其数据必须署名 AI HOT 并可回链站内 permalink
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

  static const String _host = 'aihot.virxact.com';

  /// AI HOT 站点首页，「全部」按钮在拿不到 canonical 时的回落地址。
  static const String siteUrl = 'https://aihot.virxact.com/';
  static const String _itemsPath = '/api/public/items';
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
        'take': '${take.clamp(1, 50)}',
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

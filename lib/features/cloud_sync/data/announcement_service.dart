import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/cloud_sync_models.dart';
import 'cloud_sync_client.dart';

/// 公告本地状态：缓存 + 已读集合。
class AnnouncementState {
  const AnnouncementState({
    required this.items,
    required this.readIds,
    required this.fetchedAt,
    required this.fromCache,
  });

  final List<AnnouncementEntry> items;
  final Set<String> readIds;
  final DateTime? fetchedAt;

  /// true 表示这批数据来自本地缓存（网络失败降级）。
  final bool fromCache;

  int get unreadCount => items.where((e) => !readIds.contains(e.id)).length;

  bool get hasUnread => unreadCount > 0;

  bool isRead(String id) => readIds.contains(id);

  /// 展示顺序：置顶优先，其次按发布时间倒序。
  List<AnnouncementEntry> get sorted {
    final list = [...items];
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.publishedAt.compareTo(a.publishedAt);
    });
    return list;
  }

  static const AnnouncementState empty = AnnouncementState(
    items: <AnnouncementEntry>[],
    readIds: <String>{},
    fetchedAt: null,
    fromCache: false,
  );
}

/// 公告服务：拉取、缓存、已读标记。
///
/// 去重靠公告 id 落在 [readIdsKey]；公告删除后 id 不再下发，已读集合会在下次
/// 拉取时按现存公告收敛，避免无限增长。
class AnnouncementService {
  AnnouncementService({CloudSyncClient? client, SharedPreferences? prefs})
      : _client = client ?? CloudSyncClient(),
        _injectedPrefs = prefs;

  final CloudSyncClient _client;
  final SharedPreferences? _injectedPrefs;

  static const String readIdsKey = 'box_announcement_read_ids_v1';
  static const String cacheKey = 'box_announcement_cache_v1';
  static const String cacheAtKey = 'box_announcement_cached_at_v1';

  Future<SharedPreferences> _prefs() async =>
      _injectedPrefs ?? await SharedPreferences.getInstance();

  /// 拉取公告。网络失败时回落到本地缓存，并把 fromCache 标记为 true。
  Future<AnnouncementState> load({bool force = false}) async {
    final prefs = await _prefs();
    final readIds = _readIds(prefs);
    try {
      final items = await _client.fetchAnnouncements();
      await _writeCache(prefs, items);
      // 已读集合收敛：只保留仍然存在的公告 id。
      final liveIds = items.map((e) => e.id).toSet();
      final converged = readIds.intersection(liveIds);
      if (converged.length != readIds.length) {
        await _writeReadIds(prefs, converged);
      }
      return AnnouncementState(
        items: items,
        readIds: converged,
        fetchedAt: DateTime.now(),
        fromCache: false,
      );
    } catch (e) {
      debugPrint('[AnnouncementService] 拉取公告失败，使用缓存: $e');
      final cached = _readCache(prefs);
      if (cached.isEmpty && !force) rethrow;
      return AnnouncementState(
        items: cached,
        readIds: readIds,
        fetchedAt: DateTime.tryParse(prefs.getString(cacheAtKey) ?? ''),
        fromCache: true,
      );
    }
  }

  /// 只读本地缓存，不打网络。用于给入口红点做首帧渲染。
  Future<AnnouncementState> loadCachedOnly() async {
    final prefs = await _prefs();
    return AnnouncementState(
      items: _readCache(prefs),
      readIds: _readIds(prefs),
      fetchedAt: DateTime.tryParse(prefs.getString(cacheAtKey) ?? ''),
      fromCache: true,
    );
  }

  Future<Set<String>> markRead(String id) async {
    final prefs = await _prefs();
    final ids = _readIds(prefs)..add(id);
    await _writeReadIds(prefs, ids);
    return ids;
  }

  Future<Set<String>> markAllRead(Iterable<String> ids) async {
    final prefs = await _prefs();
    final merged = _readIds(prefs)..addAll(ids);
    await _writeReadIds(prefs, merged);
    return merged;
  }

  Set<String> _readIds(SharedPreferences prefs) =>
      (prefs.getStringList(readIdsKey) ?? const <String>[]).toSet();

  Future<void> _writeReadIds(
    SharedPreferences prefs,
    Set<String> ids,
  ) async {
    await prefs.setStringList(readIdsKey, ids.toList(growable: false));
  }

  List<AnnouncementEntry> _readCache(SharedPreferences prefs) {
    final raw = prefs.getString(cacheKey);
    if (raw == null || raw.trim().isEmpty) return const <AnnouncementEntry>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <AnnouncementEntry>[];
      return decoded
          .whereType<Map>()
          .map((e) => AnnouncementEntry.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <AnnouncementEntry>[];
    }
  }

  Future<void> _writeCache(
    SharedPreferences prefs,
    List<AnnouncementEntry> items,
  ) async {
    final payload = items
        .map(
          (e) => <String, dynamic>{
            'id': e.id,
            'title': e.title,
            'body': e.body,
            'level': e.level,
            'publishedAt': e.publishedAt.toIso8601String(),
            'pinned': e.pinned,
            'linkUrl': e.linkUrl,
          },
        )
        .toList(growable: false);
    await prefs.setString(cacheKey, jsonEncode(payload));
    await prefs.setString(cacheAtKey, DateTime.now().toIso8601String());
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../novel/pages/source_manager/book_source_manager.dart';
import '../../../novel/pages/source_manager/book_source_model.dart';
import '../domain/cloud_sync_models.dart';
import 'cloud_sync_client.dart';

/// 云端书源同步：全员同一份，冲突以云端为准。
///
/// 关键难点是身份对齐。本地 [BookSourceModel.id] 是从 `url|name|sourceKind`
/// 派生的，管理员在云端给书源改名或换域名后，本地 id 会跟着变 —— 若只按新 id
/// upsert，旧条目会残留成重复项。因此这里额外维护一张
/// `云端 id -> 上次落地的本地 id` 映射表，同步时先按映射删除旧条目再写新条目。
class BookSourceCloudSyncService {
  BookSourceCloudSyncService({CloudSyncClient? client})
      : _client = client ?? CloudSyncClient();

  final CloudSyncClient _client;

  /// 本地已同步到的云端版本号。
  static const String versionKey = 'novel_cloud_book_source_version_v1';

  /// 云端 id -> 本地 BookSourceModel.id 的映射（JSON 对象）。
  static const String idMapKey = 'novel_cloud_book_source_idmap_v1';

  /// 最近一次成功同步时间（ISO8601）。
  static const String lastSyncKey = 'novel_cloud_book_source_synced_at_v1';

  /// 自动同步最小间隔，避免每次冷启动都打网络。
  static const Duration autoSyncInterval = Duration(hours: 6);

  Future<int> localVersion(SharedPreferences prefs) async =>
      prefs.getInt(versionKey) ?? -1;

  Future<DateTime?> lastSyncedAt(SharedPreferences prefs) async {
    final raw = prefs.getString(lastSyncKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// 启动时的机会性同步：距上次同步不足 [autoSyncInterval] 就直接跳过，
  /// 不打网络也不报错。失败静默（返回 null），不能因为云端不可达就卡住启动。
  Future<BookSourceSyncResult?> syncIfStale({
    required SharedPreferences prefs,
    required BookSourceManager manager,
  }) async {
    final last = await lastSyncedAt(prefs);
    if (last != null && DateTime.now().difference(last) < autoSyncInterval) {
      return null;
    }
    try {
      return await sync(prefs: prefs, manager: manager);
    } catch (e) {
      debugPrint('[BookSourceCloudSync] 自动同步失败（忽略）: $e');
      return null;
    }
  }

  /// 手动同步。[force] 为 true 时忽略本地版本号，强制拉全量。
  ///
  /// 抛 [CloudSyncException] 让调用方能把失败原因显示给用户。
  Future<BookSourceSyncResult> sync({
    required SharedPreferences prefs,
    required BookSourceManager manager,
    bool force = false,
  }) async {
    final known = prefs.getInt(versionKey);
    final bundle = await _client.fetchBookSources(
      since: force ? null : known,
    );

    if (!bundle.changed) {
      await prefs.setInt(versionKey, bundle.version);
      await prefs.setString(lastSyncKey, DateTime.now().toIso8601String());
      return BookSourceSyncResult.upToDateAt(bundle.version);
    }

    final idMap = _readIdMap(prefs);
    final existingLocalIds = manager.items.map((e) => e.id).toSet();

    var added = 0;
    var updated = 0;
    var removed = 0;
    var skipped = 0;

    // 先在内存里算出完整的增删集合，最后一次性交给 manager.applyBatch。
    // 逐条调 addOrUpdate/deleteById 会让每条都全量 jsonEncode 写盘一次
    // （N 条 = O(N²) 写盘）并触发 N 次 notifyListeners 把列表抖 N 次。
    final deleteIds = <String>[];
    final upserts = <BookSourceModel>[];

    for (final entry in bundle.sources) {
      if (entry.id.isEmpty) {
        skipped++;
        continue;
      }
      final previousLocalId = idMap[entry.id];

      if (entry.removed) {
        if (previousLocalId != null &&
            existingLocalIds.contains(previousLocalId)) {
          deleteIds.add(previousLocalId);
          existingLocalIds.remove(previousLocalId);
          removed++;
        }
        idMap.remove(entry.id);
        continue;
      }

      final model = _toModel(entry);
      if (model == null) {
        skipped++;
        continue;
      }

      // 云端改名/换域名会让派生 id 变化：先清掉映射里的旧条目，避免残留重复。
      if (previousLocalId != null && previousLocalId != model.id) {
        if (existingLocalIds.contains(previousLocalId)) {
          deleteIds.add(previousLocalId);
          existingLocalIds.remove(previousLocalId);
        }
      }

      final isNew = !existingLocalIds.contains(model.id);
      upserts.add(model);
      existingLocalIds.add(model.id);
      idMap[entry.id] = model.id;
      if (isNew) {
        added++;
      } else {
        updated++;
      }
    }

    // applyBatch 内部保证「先删后写」，与上面累积的顺序语义一致：
    // 改名场景下旧 id 在 deleteIds、新条目在 upserts，不会互相覆盖。
    await manager.applyBatch(deleteIds: deleteIds, upserts: upserts);

    await _writeIdMap(prefs, idMap);
    await prefs.setInt(versionKey, bundle.version);
    await prefs.setString(lastSyncKey, DateTime.now().toIso8601String());

    return BookSourceSyncResult(
      version: bundle.version,
      added: added,
      updated: updated,
      removed: removed,
      skipped: skipped,
      upToDate: false,
    );
  }

  /// 把云端条目转成本地书源模型。
  ///
  /// rawJson 是完整书源规则，优先用它；服务端已保证至少写入
  /// `{bookSourceName, bookSourceUrl}` 的最小规则。云端的
  /// name/url/group/enabled/weight 覆盖 rawJson 内的同名字段（云端为准）。
  BookSourceModel? _toModel(CloudBookSourceEntry entry) {
    Map<String, dynamic> base;
    try {
      final decoded = jsonDecode(entry.rawJson);
      base = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      base = <String, dynamic>{};
    }
    final name = entry.name.trim().isNotEmpty
        ? entry.name.trim()
        : (base['bookSourceName']?.toString() ?? '').trim();
    final url = entry.url.trim().isNotEmpty
        ? entry.url.trim()
        : (base['bookSourceUrl']?.toString() ?? '').trim();
    if (name.isEmpty || url.isEmpty) return null;

    base['bookSourceName'] = name;
    base['bookSourceUrl'] = url;
    if (entry.group.trim().isNotEmpty) {
      base['bookSourceGroup'] = entry.group.trim();
    }
    base['enabled'] = entry.enabled;
    if (entry.weight != 0) base['weight'] = entry.weight;
    try {
      return BookSourceModel.fromJson(base);
    } catch (e) {
      debugPrint('[BookSourceCloudSync] 跳过一条无法解析的云端书源: $e');
      return null;
    }
  }

  Map<String, String> _readIdMap(SharedPreferences prefs) {
    final raw = prefs.getString(idMapKey);
    if (raw == null || raw.trim().isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      )..removeWhere((_, value) => value.isEmpty);
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _writeIdMap(
    SharedPreferences prefs,
    Map<String, String> map,
  ) async {
    await prefs.setString(idMapKey, jsonEncode(map));
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/core/storage/cache_store.dart';
import 'models.dart';
import 'novel_cache_keys.dart';
import 'novel_repository.dart';
import 'offline_book_info.dart';

/// 离线缓存服务
///
/// 管理"标记离线"的书籍，支持：
/// - 标记/取消标记离线书并持久化元数据
/// - 后台批量预下载章节
/// - 查询已缓存章节数和估算大小
/// - 清除特定书或全部书的缓存
class OfflineCacheService {
  OfflineCacheService({
    required this.cache,
    required this.repository,
  });

  final CacheStore cache;

  /// 需要仓库引用，以便调用 fetchChapter 触发自动写缓存
  final NovelRepository repository;

  /// 旧版：存储 `Set<String>` 书 ID
  static const String _offlineKey = 'offline_cached_books_v2';

  /// 新版：存储 List<Map> 元数据（id, title, author, cover, totalChapters）
  static const String _metaKey = 'offline_books_meta_v3';

  /// 单章缓存体积估算基准（~3KB）。
  ///
  /// 之前两处统计分别写成 `cached * 3` 和 `cached * 3072`，
  /// 同一字段出现 1024 倍差异，列表页体积显示忽大忽小；统一到此常量。
  static const int _bytesPerChapter = 3072;

  // ---------------------------------------------------------------------------
  // 标记管理
  // ---------------------------------------------------------------------------

  /// 标记书为离线缓存，并开始后台预下载所有章节
  Future<void> markForOffline(NovelDetail detail) async {
    final bookId = detail.book.id;
    final prefs = await SharedPreferences.getInstance();

    // 1) 写入 ID 集合（兼容旧架构）
    final ids = _loadSet(prefs, _offlineKey);
    ids.add(bookId);
    await _saveSet(prefs, _offlineKey, ids);

    // 2) 写入元数据
    await _upsertMeta(prefs, OfflineBookInfo.fromNovelDetail(detail));

    // 3) 异步预下载
    unawaited(_prefetchAll(detail).catchError((_) {}));
  }

  /// 取消离线标记，并清除所有已缓存的章节
  Future<void> unmarkOffline(NovelDetail detail) async {
    final prefs = await SharedPreferences.getInstance();
    await _removeFromOfflineSet(prefs, detail.book.id);
    await _removeMetaById(prefs, detail.book.id);
    await _clearChapterCache(detail);
  }

  /// 仅取消离线标记，不清除缓存（书架场景：不持有 NovelDetail）
  Future<void> unmarkOfflineById(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    await _removeFromOfflineSet(prefs, bookId);
    await _removeMetaById(prefs, bookId);
  }

  /// 批量取消多本书的离线标记
  Future<void> unmarkMultiple(Iterable<NovelDetail> details) async {
    final ids = details.map((d) => d.book.id).toSet();
    final prefs = await SharedPreferences.getInstance();

    final current = _loadSet(prefs, _offlineKey);
    current.removeAll(ids);
    await _saveSet(prefs, _offlineKey, current);

    final metas = _loadMetaList(prefs);
    metas.removeWhere((m) => ids.contains(m.id));
    await _saveMetaList(prefs, metas);

    for (final detail in details) {
      await _clearChapterCache(detail).catchError((_) {});
    }
  }

  /// 检查是否已标记离线
  Future<bool> isMarkedOffline(String bookId) async {
    final ids = await getOfflineBookIds();
    return ids.contains(bookId);
  }

  /// 获取所有离线书 ID 集合
  Future<Set<String>> getOfflineBookIds() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadSet(prefs, _offlineKey);
  }

  /// 批量检查哪些书已标记离线（批量查询优化）
  Future<Set<String>> filterOfflineBooks(Iterable<String> bookIds) async {
    final ids = await getOfflineBookIds();
    return bookIds.where((id) => ids.contains(id)).toSet();
  }

  // ---------------------------------------------------------------------------
  // 元数据 / 统计查询
  // ---------------------------------------------------------------------------

  /// 获取所有离线书的元数据列表（无缓存统计）
  Future<List<OfflineBookInfo>> getOfflineMetas() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadMetaList(prefs);
  }

  /// 获取所有离线书的完整信息（含缓存章节数 + 估算大小）
  Future<List<OfflineBookInfo>> getOfflineBookInfos() async {
    final metas = await getOfflineMetas();
    if (metas.isEmpty) return [];

    final results = <OfflineBookInfo>[];
    for (final meta in metas) {
      final info = await _enrichWithCacheStats(meta);
      results.add(info);
    }
    return results;
  }

  /// 统计某本书已缓存的章节数
  Future<int> countCachedChapters(NovelDetail detail) async {
    int count = 0;
    for (final ch in detail.chapters) {
      if (ch.url.trim().isEmpty) continue;
      final data = await cache.read(NovelCacheKeys.chapter(ch.url.trim()));
      if (data != null) count++;
    }
    return count;
  }

  /// 批量统计多本书的缓存章节数（返回 bookId → 缓存数）
  Future<Map<String, int>> countCachedMultiple(
    Iterable<NovelDetail> details,
  ) async {
    final result = <String, int>{};
    for (final detail in details) {
      result[detail.book.id] = await countCachedChapters(detail);
    }
    return result;
  }

  /// 通过 detail URL 加载统计信息
  Future<OfflineBookInfo> loadDetailAndCount(OfflineBookInfo meta) async {
    try {
      final detail = await repository.fetchDetail(
        bookId: meta.id,
        detailUrl: meta.id, // 用 id 作为 detailUrl
        forceRefresh: false,
      );
      final cached = await countCachedChapters(detail);
      return meta.copyWith(
        cachedChapters: cached,
        totalChapters: detail.chapters.length,
        estimatedBytes: cached * _bytesPerChapter,
      );
    } catch (_) {
      // 加载失败 → 不展示缓存统计
    }
    return meta.copyWith(cachedChapters: -1);
  }

  // ---------------------------------------------------------------------------
  // 缓存清除
  // ---------------------------------------------------------------------------

  /// 清除某本书的章节缓存（需完整 NovelDetail）
  Future<void> clearChapterCache(NovelDetail detail) async {
    await _clearChapterCache(detail);
  }

  /// 通过 ID 清除缓存：加载 detail 后清除
  Future<bool> clearCacheById(String bookId) async {
    try {
      final detail = await repository.fetchDetail(
        bookId: bookId,
        detailUrl: bookId,
        forceRefresh: false,
      );
      await _clearChapterCache(detail);
      return true;
    } catch (_) {}
    return false;
  }

  /// 清除全部离线缓存（标记 + 元数据 + 章节数据）
  ///
  /// 章节正文直接走 [CacheStore.clear] 整目录删除，不再依赖 TTL 过期，
  /// 保证用户点完"清除缓存"磁盘占用立刻下降。
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_offlineKey);
    await prefs.remove(_metaKey);
    try {
      await cache.clear();
    } catch (_) {
      // 整目录清理失败时不影响标记与元数据已被清空
    }
  }

  /// 清除全部缓存并尝试逐本清除章节
  ///
  /// [clearAll] 已经整目录清空，这里无需再逐本拉取 detail 联网清理。
  Future<void> clearAllWithChapters() async {
    await clearAll();
  }

  /// 当前离线缓存实际占用的磁盘字节数
  Future<int> totalCacheBytes() async {
    try {
      return await cache.sizeInBytes();
    } catch (_) {
      return 0;
    }
  }

  // ---------------------------------------------------------------------------
  // 预下载
  // ---------------------------------------------------------------------------

  /// 预下载后续 N 章（阅读器触发，后台逐步执行）
  Future<void> prefetchNext(
    NovelDetail detail,
    int fromIndex, {
    int count = 30,
  }) async {
    final end = (fromIndex + count).clamp(0, detail.chapters.length);
    for (int i = fromIndex; i < end; i++) {
      await _downloadSilently(detail, i);
    }
  }

  /// 静默下载一章，失败不抛异常
  Future<void> _downloadSilently(NovelDetail detail, int chapterIndex) async {
    final url = detail.chapters[chapterIndex].url.trim();
    if (url.isEmpty) return;
    try {
      await repository.fetchChapter(
        detail: detail,
        chapterIndex: chapterIndex,
        forceRefresh: false,
      );
    } catch (_) {
      // 静默忽略
    }
  }

  /// 预下载所有章节（分批并发 + 间隔）
  Future<void> _prefetchAll(NovelDetail detail) async {
    for (int start = 0; start < detail.chapters.length; start += 5) {
      final end = (start + 5).clamp(0, detail.chapters.length);
      await Future.wait(
        List.generate(
          end - start,
          (i) => _downloadSilently(detail, start + i),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  // ---------------------------------------------------------------------------
  // 缓存清除（内部）
  // ---------------------------------------------------------------------------

  /// 清除某本书的章节缓存
  Future<void> _clearChapterCache(NovelDetail detail) async {
    for (final ch in detail.chapters) {
      if (ch.url.trim().isEmpty) continue;
      try {
        await cache.remove(NovelCacheKeys.chapter(ch.url.trim()));
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // 元数据读写
  // ---------------------------------------------------------------------------

  Future<void> _upsertMeta(SharedPreferences prefs, OfflineBookInfo info) async {
    final list = _loadMetaList(prefs);
    final idx = list.indexWhere((m) => m.id == info.id);
    if (idx >= 0) {
      list[idx] = info;
    } else {
      list.add(info);
    }
    await _saveMetaList(prefs, list);
  }

  Future<void> _removeMetaById(SharedPreferences prefs, String bookId) async {
    final list = _loadMetaList(prefs);
    list.removeWhere((m) => m.id == bookId);
    await _saveMetaList(prefs, list);
  }

  List<OfflineBookInfo> _loadMetaList(SharedPreferences prefs) {
    final raw = prefs.getString(_metaKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is List) {
        return parsed
            .whereType<Map>()
            .map((e) => OfflineBookInfo.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _saveMetaList(SharedPreferences prefs, List<OfflineBookInfo> list) async {
    final json = jsonEncode(list.map((e) => e.toJson()).toList());
    await prefs.setString(_metaKey, json);
  }

  // ---------------------------------------------------------------------------
  // 缓存统计辅助
  // ---------------------------------------------------------------------------

  Future<OfflineBookInfo> _enrichWithCacheStats(OfflineBookInfo meta) async {
    try {
      final detail = await repository.fetchDetail(
        bookId: meta.id,
        detailUrl: meta.id,
        forceRefresh: false,
      );
      int cached = 0;
      for (final ch in detail.chapters) {
        if (ch.url.trim().isEmpty) continue;
        final data = await cache.read(NovelCacheKeys.chapter(ch.url.trim()));
        if (data != null) {
          cached++;
          // 粗略估算大小（第一次读取时计算）
        }
      }
      return meta.copyWith(
        cachedChapters: cached,
        totalChapters: detail.chapters.length,
        estimatedBytes: cached * _bytesPerChapter,
      );
    } catch (_) {}
    return meta;
  }

  // ---------------------------------------------------------------------------
  // SharedPreferences 操作（兼容旧版 Set<String> 格式）
  // ---------------------------------------------------------------------------

  Set<String> _loadSet(SharedPreferences prefs, String key) {
    final raw = prefs.getStringList(key);
    if (raw != null) return raw.toSet();

    // 兼容旧版 JSON 数组格式
    final json = prefs.getString(key);
    if (json == null || json.isEmpty) return {};
    try {
      final parsed = jsonDecode(json);
      if (parsed is List) {
        return parsed.map((e) => e.toString()).toSet();
      }
    } catch (_) {}
    return {};
  }

  Future<void> _saveSet(
    SharedPreferences prefs,
    String key,
    Set<String> values,
  ) async {
    await prefs.setStringList(key, values.toList());
  }

  Future<void> _removeFromOfflineSet(
    SharedPreferences prefs,
    String bookId,
  ) async {
    final current = _loadSet(prefs, _offlineKey);
    current.remove(bookId);
    await _saveSet(prefs, _offlineKey, current);
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
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
  /// 仅在**拿不到真实磁盘体积**时兜底（统计抛异常等）。正常路径已改为
  /// 累加 [CacheStore.sizeOf] 的真实字节数：章节正文从几百字到几万字不等，
  /// 拿章节数乘一个常量报给用户，那个数字没有任何信息量。
  static const int _bytesPerChapter = 3072;

  /// 预下载并发数。
  ///
  /// 原实现把并发硬编码成 `for (start += 5)` 的步长，既调不动也看不见。
  /// 提到 8：小说站点单连接延迟通常 200–500ms，5 并发下 1000 章要
  /// 200 批 × ~400ms ≈ 80s。调大能线性缩短，但过大容易被源站限流/封 IP，
  /// 8 是实测较稳的折中。
  ///
  /// 调参方向：网络好、源站宽松 → 调大（12–16 仍可用）；
  /// 出现大量 429/超时 → 调小回 4–5。
  static const int prefetchConcurrency = 8;

  /// 每批之间的固定间隔。
  ///
  /// 原实现每批无条件 `Future.delayed(50ms)`。1000 章 = 200 批 = 10 秒
  /// 纯空等，且这 10 秒完全没有换来任何好处 —— 真正需要退避的是失败重试，
  /// 不是成功路径。所以默认归零，改由 [_prefetchAll] 在批内出现失败时退避。
  static const Duration prefetchBatchDelay = Duration.zero;

  /// 批内出现失败时的退避间隔。
  ///
  /// 失败通常意味着源站限流或网络抖动，此时继续全速打只会让失败率更高。
  /// 调参方向：仍频繁失败 → 调大到 500–800ms。
  static const Duration prefetchFailureBackoff = Duration(milliseconds: 300);

  /// 正在后台预下载的书 ID。
  ///
  /// `markForOffline` 用 `unawaited` 发射 `_prefetchAll`，句柄无人持有，取消
  /// 离线标记时那批下载会一路跑到底：既白耗流量，又在 `_clearChapterCache`
  /// 删完之后把缓存重新写回（磁盘占用降不下去）。取消离线时从这里移除书 ID，
  /// `_prefetchAll` 每批开始前查一次就会停手。
  ///
  /// static：同一本书可能由书架页和详情页各自 new 一个 Service 实例操作，
  /// 取消信号必须跨实例可见。
  static final Set<String> _activePrefetches = <String>{};

  /// 取消该书在途的后台预下载（若有）。
  static void cancelPrefetch(String bookId) {
    _activePrefetches.remove(bookId);
  }

  @visibleForTesting
  static bool isPrefetching(String bookId) =>
      _activePrefetches.contains(bookId);

  @visibleForTesting
  static void resetPrefetchesForTest() => _activePrefetches.clear();

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

    // 3) 异步预下载：登记在途，取消离线时可中断
    _activePrefetches.add(bookId);
    unawaited(
      _prefetchAll(
        detail,
        isCancelled: () => !_activePrefetches.contains(bookId),
      ).whenComplete(() => _activePrefetches.remove(bookId)).catchError((_) {}),
    );
  }

  /// 取消离线标记，并清除所有已缓存的章节
  Future<void> unmarkOffline(NovelDetail detail) async {
    // 顺序关键：先停在途下载再清缓存，否则预下载会把刚删的章节写回，
    // 用户看到「已取消缓存」但磁盘占用不降。
    cancelPrefetch(detail.book.id);
    final prefs = await SharedPreferences.getInstance();
    await _removeFromOfflineSet(prefs, detail.book.id);
    await _removeMetaById(prefs, detail.book.id);
    await _clearChapterCache(detail);
  }

  /// 仅取消离线标记，不清除章节缓存（书架场景：不持有 NovelDetail）。
  ///
  /// 注意与 [unmarkOffline] 的语义差异：本方法**不删磁盘缓存**，因为没有
  /// NovelDetail 就拿不到章节 URL 列表。需要连缓存一起清的调用方必须自己再调
  /// [clearCacheById]（`offline_cache_manage_page._removeBook` 就是这么做的）。
  Future<void> unmarkOfflineById(String bookId) async {
    // 即使不清缓存，也必须停掉在途预下载：标记已移除，继续下载纯属浪费流量。
    cancelPrefetch(bookId);
    final prefs = await SharedPreferences.getInstance();
    await _removeFromOfflineSet(prefs, bookId);
    await _removeMetaById(prefs, bookId);
  }

  /// 批量取消多本书的离线标记
  Future<void> unmarkMultiple(Iterable<NovelDetail> details) async {
    final ids = details.map((d) => d.book.id).toSet();
    // 先统一停掉在途预下载，再清缓存（同 unmarkOffline 的顺序要求）。
    for (final id in ids) {
      cancelPrefetch(id);
    }
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

  /// 统计某本书已缓存的章节数。
  ///
  /// 原实现对每章做 `cache.read(key) != null`，即把整章正文读进内存 + jsonDecode
  /// 一遍，只为了数个数；而且是 for 循环里逐个 await 串行 IO。一本 1000 章的书
  /// 打开一次离线管理页就要串行读解 1000 个文件 —— 这是「缓存很慢」的主因。
  ///
  /// 现在改为 [CacheStore.exists] 轻量探测（只看文件是否存在 + 读文件头判 TTL，
  /// 不碰正文），并分批并发执行。
  Future<int> countCachedChapters(NovelDetail detail) async {
    final keys = _chapterKeys(detail);
    if (keys.isEmpty) return 0;

    var count = 0;
    for (var start = 0; start < keys.length; start += _statConcurrency) {
      final end = (start + _statConcurrency).clamp(0, keys.length);
      final flags = await Future.wait([
        for (var i = start; i < end; i++) cache.exists(keys[i]),
      ]);
      count += flags.where((hit) => hit).length;
    }
    return count;
  }

  /// 统计并发度：纯本地文件探测，比网络请求便宜得多，可以开大。
  static const int _statConcurrency = 32;

  /// 非空章节 URL 对应的缓存键列表。
  static List<String> _chapterKeys(NovelDetail detail) {
    final keys = <String>[];
    for (final ch in detail.chapters) {
      final url = ch.url.trim();
      if (url.isEmpty) continue;
      keys.add(NovelCacheKeys.chapter(url));
    }
    return keys;
  }

  /// 已缓存章节数 + 真实磁盘占用字节数。
  ///
  /// 一趟扫完同时拿到两个数字，避免统计页先数一遍再量一遍体积。
  Future<({int cached, int bytes})> _cacheStatsFor(NovelDetail detail) async {
    final keys = _chapterKeys(detail);
    if (keys.isEmpty) return (cached: 0, bytes: 0);

    var cached = 0;
    var bytes = 0;
    for (var start = 0; start < keys.length; start += _statConcurrency) {
      final end = (start + _statConcurrency).clamp(0, keys.length);
      final sizes = await Future.wait([
        for (var i = start; i < end; i++) cache.sizeOf(keys[i]),
      ]);
      for (final size in sizes) {
        if (size > 0) {
          cached++;
          bytes += size;
        }
      }
    }
    return (cached: cached, bytes: bytes);
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
      final stats = await _cacheStatsFor(detail);
      return meta.copyWith(
        cachedChapters: stats.cached,
        totalChapters: detail.chapters.length,
        // 真实磁盘字节；万一量不到（全部 sizeOf 失败）再退回常量估算，
        // 免得体积显示成 0 让用户以为没缓存。
        estimatedBytes: stats.bytes > 0
            ? stats.bytes
            : stats.cached * _bytesPerChapter,
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
    } catch (e, st) {
      // 静默 false 会让「清除缓存」按钮看起来没反应，用户只能反复点。
      debugPrint('[OfflineCacheService] 清除缓存失败 bookId=$bookId: $e\n$st');
    }
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

  /// 预下载后续 N 章（阅读器触发，后台逐步执行）。
  ///
  /// [isCancelled] 每章开始前检查一次：返回 true 就立刻停止剩余下载。
  /// 阅读器退出时必须传这个回调，否则用户点开一章后马上返回，这 30 个请求
  /// 仍会跑完，白耗流量并挤占前台请求带宽。
  Future<void> prefetchNext(
    NovelDetail detail,
    int fromIndex, {
    int count = 30,
    bool Function()? isCancelled,
  }) async {
    final end = (fromIndex + count).clamp(0, detail.chapters.length);
    for (int i = fromIndex; i < end; i++) {
      if (isCancelled?.call() ?? false) return;
      await _downloadSilently(detail, i);
    }
  }

  /// 静默下载一章，失败不抛异常。
  ///
  /// 返回是否成功 —— [_prefetchAll] 用它决定要不要退避：
  /// 成功路径全速跑，出现失败才让一让（限流/抖动时继续全速只会更糟）。
  Future<bool> _downloadSilently(NovelDetail detail, int chapterIndex) async {
    final url = detail.chapters[chapterIndex].url.trim();
    if (url.isEmpty) return true;
    try {
      await repository.fetchChapter(
        detail: detail,
        chapterIndex: chapterIndex,
        forceRefresh: false,
      );
      return true;
    } catch (_) {
      // 静默忽略：单章失败不该中断整本预下载。
      return false;
    }
  }

  /// 预下载所有章节（分批并发 + 间隔）。
  ///
  /// [isCancelled] 每批开始前检查一次。整本书可能上千章，没有取消开关时
  /// 用户取消缓存后下载仍会跑到底，并把刚清掉的缓存重新写回。
  Future<void> _prefetchAll(
    NovelDetail detail, {
    bool Function()? isCancelled,
  }) async {
    final total = detail.chapters.length;
    for (int start = 0; start < total; start += prefetchConcurrency) {
      if (isCancelled?.call() ?? false) return;
      final end = (start + prefetchConcurrency).clamp(0, total);
      final results = await Future.wait(
        List.generate(
          end - start,
          (i) => _downloadSilently(detail, start + i),
        ),
      );

      // 只在批内出现失败时退避。原实现每批无条件等 50ms，
      // 1000 章 = 200 批 = 10 秒纯空等，且没换来任何好处。
      if (results.contains(false)) {
        await Future.delayed(prefetchFailureBackoff);
      } else if (prefetchBatchDelay > Duration.zero) {
        await Future.delayed(prefetchBatchDelay);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 缓存清除（内部）
  // ---------------------------------------------------------------------------

  /// 清除某本书的章节缓存。
  ///
  /// 分批并发删除：原实现逐章串行 await，千章书清一次缓存要等上千次
  /// 文件系统往返，用户会觉得「点了清除半天没反应」。
  Future<void> _clearChapterCache(NovelDetail detail) async {
    final keys = _chapterKeys(detail);
    for (var start = 0; start < keys.length; start += _statConcurrency) {
      final end = (start + _statConcurrency).clamp(0, keys.length);
      await Future.wait([
        for (var i = start; i < end; i++) _removeQuietly(keys[i]),
      ]);
    }
  }

  Future<void> _removeQuietly(String key) async {
    try {
      await cache.remove(key);
    } catch (e) {
      // 单章删不掉不该中断整本清理，但要留痕：
      // 静默会让「已清除」与磁盘实际占用长期不一致。
      debugPrint('[OfflineCacheService] 章节缓存删除失败 key=$key: $e');
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
    } catch (e) {
      // 失败表现为「离线书架里的书全没了」，静默会让这类故障无从定性。
      debugPrint('[OfflineCacheService] 离线书单解析失败，已降级为空列表: $e');
    }
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
      // 一趟拿到章节数 + 真实字节数，不再逐章 read 全量解码，
      // 也不再用「章节数 × 3072」冒充磁盘占用。
      final stats = await _cacheStatsFor(detail);
      return meta.copyWith(
        cachedChapters: stats.cached,
        totalChapters: detail.chapters.length,
        estimatedBytes: stats.bytes,
      );
    } catch (e) {
      // 统计失败就退回未补全的 meta：书架卡片会显示旧的缓存章节数。
      // 数字对不上时能从日志看出是统计炸了，而不是真的没缓存。
      debugPrint('[OfflineCacheService] 缓存统计失败 bookId=${meta.id}: $e');
    }
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

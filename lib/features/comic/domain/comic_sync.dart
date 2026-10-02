// 漫画收藏 / 阅读进度的**跨设备同步**（2026-10-02，第三批）。
//
// 落在哪：主服务端上那条**已有的**运维 API（`/opsapi/`）里新加的 `sync` 动作。
// 为什么不另起一个服务：那里已经有设备令牌 + 作用域 + 审计 + 边缘 nginx 入口，
// 漫画同步要的恰好就是这几样；再起一个等于把同一套抄一遍，还多一个端口/单元/令牌表。
//
// 三层，各管一件事：
//   * [ComicSyncDoc]  —— 线上那份「收藏 + 进度」长什么样（它的 JSON 就是 HTTP body）；
//   * [ComicSyncMerge] —— **与服务端同一套合并规则**：按 key 逐条"谁的时间新听谁的"，
//     删除用墓碑（`removed: true` + updatedAt），否则"在一台机器上删掉的书"会在另一台上复活；
//   * [ComicSyncService] —— 拉 → 合并 → 落本地 → 推回；全程最好-effort，失败只记在状态里，
//     绝不挡开页面/翻页（同步是"顺带做好的事"，不是用户等着的事）。
//
// 身份：用**设备令牌**（与只读运维 API 同一把，手机那两把 `box-app-*` 都带 write 作用域），
// 令牌只进请求头、绝不落盘/进日志。没配令牌 = 静默不做（不是错误：没配过就没这回事）。
library;


import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_api_client.dart';

import 'comic_book.dart';
import 'comic_library_store.dart';
import 'comic_online_progress.dart';

/// 一次同步的结果（给界面显示用，也方便用例断言）。
class ComicSyncOutcome {
  const ComicSyncOutcome({
    this.ok = false,
    this.skipped = false,
    this.message = '',
    this.addedBooks = 0,
    this.removedBooks = 0,
    this.progressUpdated = 0,
  });

  /// 这次真的和服务器说上话了。
  final bool ok;

  /// 没做（没配令牌 / 没开同步）：不算失败，界面别说"同步失败"。
  final bool skipped;
  final String message;

  /// 从别处同步过来的：新增的收藏 / 被别处删掉的收藏 / 更新的进度。
  final int addedBooks;
  final int removedBooks;
  final int progressUpdated;

  @override
  String toString() =>
      'ok=$ok skipped=$skipped added=$addedBooks removed=$removedBooks '
      'progress=$progressUpdated $message';
}

/// 线上那份同步档。
class ComicSyncDoc {
  const ComicSyncDoc({
    this.books = const <Map<String, dynamic>>[],
    this.progress = const <String, Map<String, dynamic>>{},
    this.updatedAt = '',
  });

  /// 收藏条目：`ComicBook.toJson()` + `bookUrl` + `updatedAt`；删除的条目带 `removed: true`。
  final List<Map<String, dynamic>> books;

  /// 阅读进度：`bookUrl → ComicOnlineProgress.toJson()`。
  final Map<String, Map<String, dynamic>> progress;
  final String updatedAt;

  List<Map<String, dynamic>> get liveBooks =>
      [for (final b in books) if (b['removed'] != true) b];

  factory ComicSyncDoc.fromJson(Map<String, dynamic> json) {
    final books = <Map<String, dynamic>>[];
    final rawBooks = json['books'];
    if (rawBooks is List) {
      for (final b in rawBooks) {
        if (b is Map) books.add(Map<String, dynamic>.from(b));
      }
    }
    final progress = <String, Map<String, dynamic>>{};
    final rawProgress = json['progress'];
    if (rawProgress is Map) {
      rawProgress.forEach((k, v) {
        if (v is Map) progress[k.toString()] = Map<String, dynamic>.from(v);
      });
    }
    return ComicSyncDoc(
      books: books,
      progress: progress,
      updatedAt: json['updatedAt']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'books': books,
    'progress': progress,
    'updatedAt': updatedAt,
  };
}

/// 合并规则（与服务端 `merge_sync` 一致，两边各有一份用例钉住同一组事实）。
class ComicSyncMerge {
  static String _ts(Object? item) {
    if (item is Map) {
      final v = item['updatedAt'];
      if (v is String) return v;
      if (v is num) {
        return DateTime.fromMillisecondsSinceEpoch(v.toInt()).toIso8601String();
      }
    }
    return '';
  }

  static ComicSyncDoc merge(ComicSyncDoc a, ComicSyncDoc b) {
    final books = <String, Map<String, dynamic>>{};
    for (final src in [a.books, b.books]) {
      for (final book in src) {
        final key = (book['bookUrl'] ?? book['onlineUrl'] ?? '').toString();
        if (key.isEmpty) continue;
        final old = books[key];
        // 同时间取后者：两台设备的同一条记录内容一致，取谁都一样（避免抖动）。
        if (old == null || _ts(book).compareTo(_ts(old)) >= 0) {
          books[key] = book;
        }
      }
    }
    final progress = <String, Map<String, dynamic>>{};
    for (final src in [a.progress, b.progress]) {
      src.forEach((key, value) {
        if (key.isEmpty) return;
        final old = progress[key];
        if (old == null || _ts(value).compareTo(_ts(old)) >= 0) {
          progress[key] = value;
        }
      });
    }
    final updated = _ts(a.toJson()).compareTo(_ts(b.toJson())) >= 0
        ? a.updatedAt
        : b.updatedAt;
    final keys = books.keys.toList()..sort();
    return ComicSyncDoc(
      books: [for (final k in keys) books[k]!],
      progress: progress,
      updatedAt: updated,
    );
  }
}

/// 同步服务。一台设备一份档（服务端按令牌 label 分文件），合并交给 [ComicSyncMerge]。
class ComicSyncService {
  ComicSyncService({
    required OpsApiClient api,
    ComicLibraryStore? libraryStore,
    ComicOnlineProgressStore? progressStore,
    CacheStore? cacheStore,
  }) : _api = api,
       _library = libraryStore ?? ComicLibraryStore(),
       _progress = progressStore ?? ComicOnlineProgressStore(),
       _cache = cacheStore ?? CacheStore(namespace: 'comic_sync');

  final OpsApiClient _api;
  final ComicLibraryStore _library;
  final ComicOnlineProgressStore _progress;
  final CacheStore _cache;

  static const String _keyRemoved = 'removed';
  static const String _keyLastSync = 'last_sync_at';
  static const String _keyLastMessage = 'last_message';

  /// 上次同步时间（没同步过 = null）。
  Future<DateTime?> lastSyncAt() async {
    final raw = await _cache.read(_keyLastSync);
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  Future<String> lastMessage() async {
    final raw = await _cache.read(_keyLastMessage);
    return raw is String ? raw : '';
  }

  /// 本地记着"这本书被删了"（墓碑）。界面删收藏时要叫一下它，否则删除传不出去。
  Future<void> recordRemoved(String bookUrl) async {
    if (bookUrl.trim().isEmpty) return;
    final list = await _removed();
    list.removeWhere((e) => e['bookUrl'] == bookUrl);
    list.add({
      'bookUrl': bookUrl,
      'removed': true,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await _cache.write(_keyRemoved, list);
  }

  Future<List<Map<String, dynamic>>> _removed() async {
    final raw = await _cache.read(_keyRemoved);
    if (raw is! List) return <Map<String, dynamic>>[];
    return [
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  /// 本地这份档（**只收在线书**：本地文件的路径换台机器就没意义，同步过去只会多一堆打不开的书）。
  Future<ComicSyncDoc> localDoc() async {
    final books = <Map<String, dynamic>>[];
    for (final book in await _library.fetch()) {
      if (book.sourceType != ComicSourceType.online) continue;
      final url = book.onlineUrl ?? book.id;
      if (url.trim().isEmpty) continue;
      books.add({
        ...book.toJson(),
        'bookUrl': url,
        'updatedAt': DateTime.fromMillisecondsSinceEpoch(
          book.createdAt,
        ).toIso8601String(),
      });
    }
    books.addAll(await _removed());
    final progress = <String, Map<String, dynamic>>{};
    final mine = await _progress.all();
    mine.forEach((key, p) => progress[key] = p.toJson());
    return ComicSyncDoc(
      books: books,
      progress: progress,
      updatedAt: DateTime.now().toIso8601String(),
    );
  }

  /// 拉一次、合并、落本地、推回。全程最好-effort。
  Future<ComicSyncOutcome> syncNow() async {
    if (!_api.hasToken) {
      return const ComicSyncOutcome(
        skipped: true,
        message: '还没配设备令牌（设置 → 服务器 → 设备令牌）',
      );
    }
    final local = await localDoc();
    final remoteRaw = ComicSyncDoc.fromJson(await _api.call('sync'));
    final merged = ComicSyncMerge.merge(local, remoteRaw);
    final applied = await _applyLocally(merged, local);
    // 推回合并后的全量：服务端会再合一次（幂等），这样两台设备最终看到同一份。
    final pushed = ComicSyncDoc.fromJson(await _api.post('sync', merged.toJson()));
    final at = DateTime.now();
    final msg =
        '新增 ${applied.addedBooks} 本 · 同步删除 ${applied.removedBooks} 本 · '
        '进度 ${applied.progressUpdated} 条 · 线上共 '
        '${pushed.liveBooks.length} 本';
    await _cache.write(_keyLastSync, at.toIso8601String());
    await _cache.write(_keyLastMessage, msg);
    return ComicSyncOutcome(
      ok: true,
      message: msg,
      addedBooks: applied.addedBooks,
      removedBooks: applied.removedBooks,
      progressUpdated: applied.progressUpdated,
    );
  }

  /// 把合并结果落到本机：补上别处新增的、删掉别处删掉的（**按时间判**）、更新进度。
  Future<ComicSyncOutcome> _applyLocally(
    ComicSyncDoc merged,
    ComicSyncDoc beforeLocal,
  ) async {
    final localByUrl = <String, Map<String, dynamic>>{
      for (final b in beforeLocal.books)
        if (b['removed'] != true) (b['bookUrl'] ?? '').toString(): b,
    };
    var added = 0;
    var removed = 0;
    for (final book in merged.books) {
      final url = (book['bookUrl'] ?? '').toString();
      if (url.isEmpty) continue;
      final isTombstone = book['removed'] == true;
      final mine = localByUrl[url];
      if (isTombstone) {
        // 别处删了、而且删的时间不比我加的时间旧 → 本机也删掉。
        if (mine == null) continue;
        final tombTs = (book['updatedAt'] ?? '').toString();
        final mineTs = (mine['updatedAt'] ?? '').toString();
        if (tombTs.compareTo(mineTs) < 0) continue;
        try {
          await _library.remove(url);
          removed++;
        } catch (_) {
          // 删不掉不算错（下次同步还会再来一遍）。
        }
        continue;
      }
      if (mine != null) continue;
      try {
        await _library.add(ComicBook.fromJson(book));
        added++;
      } catch (_) {
        // 坏条目跳过：一条脏数据不该让整次同步失败。
      }
    }
    var progressUpdated = 0;
    final localProgress = beforeLocal.progress;
    for (final entry in merged.progress.entries) {
      final mine = localProgress[entry.key];
      final mineTs = (mine?['updatedAt'] ?? '').toString();
      final itsTs = (entry.value['updatedAt'] ?? '').toString();
      if (mine != null && itsTs.compareTo(mineTs) <= 0) continue;
      final p = ComicOnlineProgress.fromJson(entry.value);
      if (p == null) continue;
      try {
        await _progress.save(p);
        progressUpdated++;
      } catch (_) {
        // 同上：单条失败跳过。
      }
    }
    return ComicSyncOutcome(
      addedBooks: added,
      removedBooks: removed,
      progressUpdated: progressUpdated,
    );
  }
}

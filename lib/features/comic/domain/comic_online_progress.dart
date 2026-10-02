// 在线漫画的阅读进度：`书地址 → 读到哪一话、第几页`。
//
// 用与本地书架同一套存储（CacheStore），所以"清数据"这两件事是一起被清掉的，
// 不会出现"书架没了、进度还在"这种对不上的状态。
library;

import 'package:box/core/storage/cache_store.dart';

/// 一本书的在线阅读进度。
class ComicOnlineProgress {
  const ComicOnlineProgress({
    required this.bookUrl,
    required this.chapterUrl,
    this.chapterTitle = '',
    this.index = 0,
    this.updatedAt,
  });

  final String bookUrl;
  final String chapterUrl;
  final String chapterTitle;

  /// 读到这一话的第几张（0 起）。
  final int index;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
    'bookUrl': bookUrl,
    'chapterUrl': chapterUrl,
    'chapterTitle': chapterTitle,
    'index': index,
    'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  static ComicOnlineProgress? fromJson(Map<String, dynamic> json) {
    final bookUrl = json['bookUrl']?.toString() ?? '';
    final chapterUrl = json['chapterUrl']?.toString() ?? '';
    if (bookUrl.isEmpty || chapterUrl.isEmpty) return null;
    return ComicOnlineProgress(
      bookUrl: bookUrl,
      chapterUrl: chapterUrl,
      chapterTitle: json['chapterTitle']?.toString() ?? '',
      index: (json['index'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}

/// 在线阅读进度存储。
class ComicOnlineProgressStore {
  ComicOnlineProgressStore({CacheStore? cacheStore})
    : _cache = cacheStore ?? CacheStore(namespace: 'comic_online_progress');

  final CacheStore _cache;

  Future<ComicOnlineProgress?> load(String bookUrl) async {
    final all = await _all();
    return all[bookUrl];
  }

  Future<void> save(ComicOnlineProgress progress) async {
    final all = await _all();
    all[progress.bookUrl] = progress;
    await _cache.write(
      'items',
      all.map((k, v) => MapEntry(k, v.toJson())),
    );
  }

  /// 全部进度（跨设备同步要的是全量，不是"最近几本"）。
  Future<Map<String, ComicOnlineProgress>> all() => _all();

  /// 最近读过的若干本（按时间倒序）。
  Future<List<ComicOnlineProgress>> recent({int limit = 5}) async {
    final all = await _all();
    final list = all.values.toList();
    list.sort(
      (a, b) => (b.updatedAt ?? DateTime(0)).compareTo(
        a.updatedAt ?? DateTime(0),
      ),
    );
    return list.take(limit).toList();
  }

  Future<void> remove(String bookUrl) async {
    final all = await _all();
    if (all.remove(bookUrl) != null) {
      await _cache.write('items', all.map((k, v) => MapEntry(k, v.toJson())));
    }
  }

  Future<Map<String, ComicOnlineProgress>> _all() async {
    final raw = await _cache.read('items');
    final out = <String, ComicOnlineProgress>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is Map) {
          final p = ComicOnlineProgress.fromJson(
            Map<String, dynamic>.from(v),
          );
          if (p != null) out[k.toString()] = p;
        }
      });
    }
    return out;
  }
}

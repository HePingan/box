// 下一话预取：行为锁。
//
// 这里锁的是"预取该怎么克制"：只认下一话、只取开头几张、最后一话不动手、
// 同一话不重复打接口、任何一步失败都不能往外抛（预取失败不该影响正在读的这一话）。

import 'dart:io';

import 'package:box/features/comic/domain/comic_image_cache.dart';
import 'package:box/features/comic/domain/comic_prefetch.dart';
import 'package:box/features/comic/domain/comic_online_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记下"取了哪些图"的假缓存（不落盘）。
class _RecordingCache extends ComicImageCache {
  final List<String> fetched = <String>[];
  final Set<String> failing = <String>{};

  /// 每次取图是不是**低优先级**（预取必须传 true：它不能占着并发名额让正文排队）。
  final List<bool> lowPriorityFlags = <bool>[];

  @override
  Future<File> fetch(String url, {bool lowPriority = false}) async {
    fetched.add(url);
    lowPriorityFlags.add(lowPriority);
    if (failing.contains(url)) throw const FileSystemException('取不到');
    return File('/dev/null');
  }
}

List<ComicChapterRef> _chapters(List<String> names) => [
      for (final n in names) ComicChapterRef(title: n, url: 'https://site/ch/$n'),
    ];

void main() {
  test('只取下一话的开头几张（当前话、再后面的话都不碰）', () async {
    final cache = _RecordingCache();
    final asked = <String>[];
    final prefetcher = ComicChapterPrefetcher(
      loadImages: (url) async {
        asked.add(url);
        // 每一话给 5 张，预取默认只要开头 3 张。
        return [for (var i = 1; i <= 5; i++) '$url/$i.jpg'];
      },
      cache: cache,
    );

    await prefetcher.prefetchNext(_chapters(['A', 'B', 'C']), 0);

    expect(asked, ['https://site/ch/B'], reason: '只问下一话');
    expect(cache.fetched, [
      'https://site/ch/B/1.jpg',
      'https://site/ch/B/2.jpg',
      'https://site/ch/B/3.jpg',
    ], reason: '只要开头 3 张（整话最多 209 张 ≈ 10MB，全取会顶满缓存上限）');
  });

  test('读到最后一话：一次都不打接口', () async {
    final cache = _RecordingCache();
    var calls = 0;
    final prefetcher = ComicChapterPrefetcher(
      loadImages: (url) async {
        calls++;
        return <String>['$url/1.jpg'];
      },
      cache: cache,
    );

    await prefetcher.prefetchNext(_chapters(['A', 'B']), 1);

    expect(calls, 0);
    expect(cache.fetched, isEmpty);
    expect(prefetcher.hasPrefetchedAnything, isFalse);
  });

  test('同一话重复触发（翻页会连着触发好几次）：只跑一趟', () async {
    final cache = _RecordingCache();
    var calls = 0;
    final prefetcher = ComicChapterPrefetcher(
      loadImages: (url) async {
        calls++;
        return ['$url/1.jpg', '$url/2.jpg'];
      },
      cache: cache,
    );
    final chapters = _chapters(['A', 'B', 'C']);

    // 并发触发（还在跑）
    await Future.wait([
      prefetcher.prefetchNext(chapters, 0),
      prefetcher.prefetchNext(chapters, 0),
      prefetcher.prefetchNext(chapters, 0),
    ]);
    // 跑完再触发一次
    await prefetcher.prefetchNext(chapters, 0);

    expect(calls, 1, reason: '接口只问一次');
    expect(cache.fetched.length, 2, reason: '图也只取一遍');
  });

  test('图列表取不到：安静收场，不往外抛；下次还能再试', () async {
    final cache = _RecordingCache();
    var calls = 0;
    final prefetcher = ComicChapterPrefetcher(
      loadImages: (url) async {
        calls++;
        if (calls == 1) throw StateError('站点挡了');
        return ['$url/1.jpg'];
      },
      cache: cache,
    );
    final chapters = _chapters(['A', 'B']);

    await prefetcher.prefetchNext(chapters, 0); // 不抛
    expect(cache.fetched, isEmpty);
    expect(prefetcher.hasPrefetchedAnything, isFalse, reason: '失败不算预取过');

    await prefetcher.prefetchNext(chapters, 0); // 还能再试
    expect(calls, 2);
    expect(cache.fetched, ['https://site/ch/B/1.jpg']);
  });

  test('某一张取不到：其余照取（不中断），也不抛', () async {
    final cache = _RecordingCache()..failing.add('https://site/ch/B/1.jpg');
    final prefetcher = ComicChapterPrefetcher(
      loadImages: (url) async => ['$url/1.jpg', '$url/2.jpg', '$url/3.jpg'],
      cache: cache,
    );

    await prefetcher.prefetchNext(_chapters(['A', 'B']), 0);

    expect(cache.fetched, [
      'https://site/ch/B/1.jpg',
      'https://site/ch/B/2.jpg',
      'https://site/ch/B/3.jpg',
    ], reason: '挂了一张不该把后面两张也丢下');
  });

  test('图列表是空的：不打无用功，也不记成预取过', () async {
    final cache = _RecordingCache();
    final prefetcher = ComicChapterPrefetcher(
      loadImages: (url) async => <String>[],
      cache: cache,
    );

    await prefetcher.prefetchNext(_chapters(['A', 'B']), 0);

    expect(cache.fetched, isEmpty);
    expect(prefetcher.hasPrefetchedAnything, isFalse);
  });

  test('预取一律标成低优先级（不能占着并发名额让正在读的这一话排队）', () async {
    final cache = _RecordingCache();
    final prefetcher = ComicChapterPrefetcher(
      loadImages: (url) async => <String>['$url/1.jpg', '$url/2.jpg'],
      cache: cache,
    );

    await prefetcher.prefetchNext(_chapters(['A', 'B']), 0);

    expect(cache.fetched, isNotEmpty);
    expect(
      cache.lowPriorityFlags.every((low) => low),
      isTrue,
      reason: '预取和正文共用同一个缓存实例 → 同一个并发池，标了低优先级正文才不被挤',
    );
  });
}

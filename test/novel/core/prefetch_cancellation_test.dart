import 'package:box/core/storage/cache_store.dart';
import 'package:box/novel/core/models.dart';
import 'package:box/novel/core/novel_repository.dart';
import 'package:box/novel/core/novel_source.dart';
import 'package:box/novel/core/offline_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：后台预取必须可取消。
///
/// 缺陷（offline_cache_service.dart:prefetchNext）：默认预取 30 章，串行 await，
/// 无任何取消机制；reader_controller 用 unawaited 发射后也没人持有句柄。
/// 用户点开一章立刻退出阅读器，这 30 个请求仍会跑完 —— 白耗流量、挤占前台带宽。
void main() {
  NovelDetail detailWith(int chapterCount) => NovelDetail(
        book: const NovelBook(
          id: 'b1',
          title: '测试书',
          author: 'A',
          intro: '',
          coverUrl: '',
          detailUrl: '/novel/b1',
        ),
        chapters: List.generate(
          chapterCount,
          (i) => NovelChapter(title: '第$i章', url: '/chapter/$i'),
        ),
      );

  ({OfflineCacheService service, _CountingSource source}) build() {
    final source = _CountingSource();
    final cache = _FakeCache(namespace: 't');
    final repo = NovelRepository(source: source, cache: cache);
    return (
      service: OfflineCacheService(repository: repo, cache: cache),
      source: source,
    );
  }

  test('立刻取消则一章都不下载', () async {
    final env = build();
    await env.service.prefetchNext(
      detailWith(30),
      0,
      count: 30,
      isCancelled: () => true,
    );
    expect(env.source.chapterCalls, 0);
  });

  test('中途取消后停止预取剩余章节（核心回归）', () async {
    final env = build();
    var downloaded = 0;
    env.source.onCall = () => downloaded++;

    // 下载到第 3 章时置位取消
    await env.service.prefetchNext(
      detailWith(30),
      0,
      count: 30,
      isCancelled: () => downloaded >= 3,
    );

    expect(env.source.chapterCalls, lessThan(30),
        reason: '取消后不得跑完全部 30 章，实际 ${env.source.chapterCalls} 章');
    expect(env.source.chapterCalls, lessThanOrEqualTo(4));
  });

  test('不传 isCancelled 时行为不变（全部下载）', () async {
    final env = build();
    await env.service.prefetchNext(detailWith(5), 0, count: 5);
    expect(env.source.chapterCalls, 5);
  });
}

class _CountingSource implements NovelSource {
  int chapterCalls = 0;
  void Function()? onCall;

  @override
  Future<ChapterContent> fetchChapter({
    required NovelDetail detail,
    required int chapterIndex,
  }) async {
    chapterCalls++;
    onCall?.call();
    return ChapterContent(
      title: '第$chapterIndex章',
      content: '甲段。\n\n乙段。\n\n丙段。',
      chapterIndex: chapterIndex,
      sourceUrl: '/chapter/$chapterIndex',
    );
  }

  @override
  Future<List<NovelBook>> searchBooks(String keyword, {int page = 1}) async =>
      const [];

  @override
  Future<List<NovelBook>> fetchByPath(String path) async => const [];

  @override
  Future<NovelDetail> fetchDetail({
    required String bookId,
    String? detailUrl,
  }) async =>
      throw UnimplementedError();
}

class _FakeCache implements CacheStore {
  _FakeCache({required this.namespace});

  final Map<String, dynamic> map = {};

  @override
  final String namespace;

  @override
  final bool webMode = false;

  @override
  Future<void> write(String key, dynamic data, {Duration? ttl}) async {
    map[key] = data;
  }

  @override
  Future<dynamic> read(String key) async => map[key];

  @override
  Future<void> remove(String key) async {
    map.remove(key);
  }

  @override
  Future<int> clear() async {
    final n = map.length;
    map.clear();
    return n;
  }

  @override
  Future<int> sizeInBytes() async => map.length;
}

import 'package:box/core/storage/cache_store.dart';
import 'package:box/novel/core/models.dart';
import 'package:box/novel/core/novel_repository.dart';
import 'package:box/novel/core/novel_source.dart';
import 'package:box/novel/core/offline_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归：取消离线标记必须中断在途的后台预下载。
///
/// 缺陷（offline_cache_service.dart:markForOffline）：
///   unawaited(_prefetchAll(detail).catchError((_) {}));
/// 句柄无人持有，_prefetchAll 没有取消信号。用户点「离线缓存」后立刻取消：
///   1. 整本书（可能上千章）继续下载到底，白耗流量；
///   2. _clearChapterCache 删完之后，在途下载又把缓存写回，磁盘占用降不下去。
/// NovelDetailController 的 _cancelCache 只管自己的循环，管不到这里。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OfflineCacheService.resetPrefetchesForTest();
  });

  NovelDetail detailWith(int n, {String id = 'b1'}) => NovelDetail(
        book: NovelBook(
          id: id,
          title: '测试书',
          author: 'A',
          intro: '',
          coverUrl: '',
          detailUrl: '/novel/$id',
        ),
        chapters: List.generate(
          n,
          (i) => NovelChapter(title: '第$i章', url: '/$id/chapter/$i'),
        ),
      );

  ({OfflineCacheService service, _SlowSource source}) build() {
    final source = _SlowSource();
    final cache = _FakeCache(namespace: 't');
    final repo = NovelRepository(source: source, cache: cache);
    return (
      service: OfflineCacheService(repository: repo, cache: cache),
      source: source,
    );
  }

  test('unmarkOffline 中断在途预下载（核心回归）', () async {
    final env = build();
    final detail = detailWith(200);

    await env.service.markForOffline(detail);
    expect(OfflineCacheService.isPrefetching('b1'), isTrue,
        reason: '预下载应已登记为在途');

    // 让前几批跑起来，然后取消
    await Future.delayed(const Duration(milliseconds: 30));
    final beforeCancel = env.source.chapterCalls;
    await env.service.unmarkOffline(detail);

    expect(OfflineCacheService.isPrefetching('b1'), isFalse);

    // 取消后再等一段，下载不应继续推进
    await Future.delayed(const Duration(milliseconds: 120));
    final afterCancel = env.source.chapterCalls;

    expect(afterCancel, lessThan(200),
        reason: '取消后不得跑完 200 章，实际 $afterCancel');
    expect(afterCancel - beforeCancel, lessThan(20),
        reason: '取消后新增下载应迅速收敛，实际新增 ${afterCancel - beforeCancel}');
  });

  test('unmarkOfflineById 同样中断在途预下载', () async {
    final env = build();
    await env.service.markForOffline(detailWith(200));
    expect(OfflineCacheService.isPrefetching('b1'), isTrue);

    await env.service.unmarkOfflineById('b1');
    expect(OfflineCacheService.isPrefetching('b1'), isFalse);

    await Future.delayed(const Duration(milliseconds: 100));
    expect(env.source.chapterCalls, lessThan(200));
  });

  test('取消一本书不影响另一本的预下载', () async {
    final env = build();
    await env.service.markForOffline(detailWith(50, id: 'b1'));
    await env.service.markForOffline(detailWith(50, id: 'b2'));

    await env.service.unmarkOfflineById('b1');

    expect(OfflineCacheService.isPrefetching('b1'), isFalse);
    expect(OfflineCacheService.isPrefetching('b2'), isTrue,
        reason: 'b2 的预下载不该被 b1 的取消波及');
  });

  test('预下载自然跑完后自动摘掉在途标记', () async {
    final env = build();
    await env.service.markForOffline(detailWith(5));
    await Future.delayed(const Duration(milliseconds: 300));
    expect(OfflineCacheService.isPrefetching('b1'), isFalse,
        reason: 'whenComplete 应清理在途登记，否则集合会泄漏');
  });
}

class _SlowSource implements NovelSource {
  int chapterCalls = 0;

  @override
  Future<ChapterContent> fetchChapter({
    required NovelDetail detail,
    required int chapterIndex,
  }) async {
    chapterCalls++;
    // 模拟真实网络延迟，让测试有机会在中途取消
    await Future.delayed(const Duration(milliseconds: 2));
    return ChapterContent(
      title: '第$chapterIndex章',
      content: '甲段。\n\n乙段。\n\n丙段。',
      chapterIndex: chapterIndex,
      sourceUrl: detail.chapters[chapterIndex].url,
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

  // CacheStore 新增的轻量探测接口（存在性判断不再全量解码正文）。
  // Fake 里 map 直接持对象，没有 TTL/文件概念，如实反映有无即可。
  @override
  Future<bool> exists(String key) async => map.containsKey(key);

  @override
  Future<int> sizeOf(String key) async => map.containsKey(key) ? 1 : 0;

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

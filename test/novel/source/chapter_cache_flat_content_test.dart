import 'package:box/core/storage/cache_store.dart';
import 'package:box/novel/core/models.dart';
import 'package:box/novel/core/novel_cache_keys.dart';
import 'package:box/novel/core/novel_repository.dart';
import 'package:box/novel/core/novel_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：旧版本写入的「整章压平成一行」的正文缓存必须被判定为失效，
/// 否则修好分段逻辑后，用户在 30 天 TTL 内读过的章节永远拿到旧的坏数据。
///
/// 这正是用户连续报「还是一段」的真实原因：修的是 fetchChapter 的解析，
/// 但 repository 层缓存命中直接 return，新解析代码根本没被执行。
void main() {
  final detail = NovelDetail(
    book: const NovelBook(
      id: 'b1',
      title: '测试书',
      author: '作者',
      intro: '',
      coverUrl: '',
      detailUrl: '/novel/b1',
    ),
    chapters: const [NovelChapter(title: '第一章', url: '/chapter/1')],
  );

  final key = NovelCacheKeys.chapter('/chapter/1');

  Map<String, dynamic> entry(String content) => {
        'title': '第一章',
        'content': content,
        'chapterIndex': 0,
        'sourceUrl': '/chapter/1',
      };

  group('章节正文缓存分段校验', () {
    test('多段正文的缓存正常命中，不重复请求网络', () async {
      final source = _FakeSource();
      final cache = _FakeCache(namespace: 't');
      await cache.write(key, entry('甲段。\n\n乙段。\n\n丙段。'));
      final repo = NovelRepository(source: source, cache: cache);

      final c = await repo.fetchChapter(detail: detail, chapterIndex: 0);

      expect(source.chapterCalls, 0, reason: '好缓存应直接命中');
      expect(c.content.contains('\n'), isTrue);
    });

    test('压平成一行的长正文旧缓存被判失效并回源（回归）', () async {
      final source = _FakeSource();
      final cache = _FakeCache(namespace: 't');
      // 旧 cleanRaw 的产物：整章一行，无任何换行
      await cache.write(key, entry('甲段内容。${'乙段内容。' * 60}'));
      final repo = NovelRepository(source: source, cache: cache);

      final c = await repo.fetchChapter(detail: detail, chapterIndex: 0);

      expect(source.chapterCalls, 1,
          reason: '压平的旧缓存必须失效并回源，否则用户永远看到一段');
      expect(c.content, contains('\n'), reason: '应拿到新解析的分段正文');
    });

    test('短正文即使无换行也不误判失效（如"本章内容为空"）', () async {
      final source = _FakeSource();
      final cache = _FakeCache(namespace: 't');
      await cache.write(key, entry('本章内容为空'));
      final repo = NovelRepository(source: source, cache: cache);

      final c = await repo.fetchChapter(detail: detail, chapterIndex: 0);

      expect(source.chapterCalls, 0, reason: '短文本无换行属正常，不应回源');
      expect(c.content, '本章内容为空');
    });

    test('回源失败时仍回退到旧缓存，不让用户空屏', () async {
      final source = _FakeSource(throwOnChapter: true);
      final cache = _FakeCache(namespace: 't');
      final flat = '甲段内容。${'乙段内容。' * 60}';
      await cache.write(key, entry(flat));
      final repo = NovelRepository(source: source, cache: cache);

      final c = await repo.fetchChapter(detail: detail, chapterIndex: 0);

      expect(source.chapterCalls, 1);
      expect(c.content, flat, reason: '网络失败时坏缓存也比空屏好');
    });

    test('forceRefresh 时始终回源', () async {
      final source = _FakeSource();
      final cache = _FakeCache(namespace: 't');
      await cache.write(key, entry('甲段。\n\n乙段。'));
      final repo = NovelRepository(source: source, cache: cache);

      await repo.fetchChapter(
        detail: detail,
        chapterIndex: 0,
        forceRefresh: true,
      );

      expect(source.chapterCalls, 1);
    });
  });
}

class _FakeSource implements NovelSource {
  _FakeSource({this.throwOnChapter = false});

  final bool throwOnChapter;
  int chapterCalls = 0;

  @override
  Future<ChapterContent> fetchChapter({
    required NovelDetail detail,
    required int chapterIndex,
  }) async {
    chapterCalls++;
    if (throwOnChapter) throw Exception('network down');
    return ChapterContent(
      title: '第一章',
      content: '新甲段。\n\n新乙段。\n\n新丙段。',
      chapterIndex: chapterIndex,
      sourceUrl: '/chapter/1',
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

import 'package:box/core/storage/cache_store.dart';
import 'package:box/novel/core/models.dart';
import 'package:box/novel/core/novel_repository.dart';
import 'package:box/novel/core/novel_source.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSource implements NovelSource {
  _FakeSource({this.books = const []});

  final List<NovelBook> books;

  int searchCalls = 0;
  int pathCalls = 0;
  int detailCalls = 0;
  int chapterCalls = 0;

  @override
  Future<List<NovelBook>> searchBooks(String keyword, {int page = 1}) async {
    searchCalls++;
    return books;
  }

  @override
  Future<List<NovelBook>> fetchByPath(String path) async {
    pathCalls++;
    return books;
  }

  @override
  Future<NovelDetail> fetchDetail({
    required String bookId,
    String? detailUrl,
  }) async {
    detailCalls++;
    return NovelDetail(
      book: NovelBook(id: bookId, title: bookId, author: '', intro: '', coverUrl: '', detailUrl: detailUrl ?? ''),
      chapters: [],
    );
  }

  @override
  Future<ChapterContent> fetchChapter({
    required NovelDetail detail,
    required int chapterIndex,
  }) async {
    chapterCalls++;
    return ChapterContent(
          title: detail.chapters.isEmpty ? 'c$chapterIndex' : detail.chapters[chapterIndex].title,
          content: 'content',
          chapterIndex: chapterIndex,
          sourceUrl: '',
          fromCache: false,
        );
  }
}

class _FakeCache implements CacheStore {
  _FakeCache({Map<String, dynamic>? map, required this.namespace})
      : map = Map<String, dynamic>.from(map ?? const {});

  final Map<String, dynamic> map;
  @override
  final String namespace;
  @override final bool webMode = false;
  final Map<String, dynamic> written = {};
  final int removed = 0;

  @override
  Future<void> write(String key, dynamic data, {Duration? ttl}) async {
    written[key] = data;
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
  Future<void> remove(String key) async {}

  @override
  Future<int> clear() async {
    final count = map.length;
    map.clear();
    return count;
  }

  @override
  Future<int> sizeInBytes() async => map.length;
}

void main() {
  group('NovelRepository', () {
    test('searchBooks caches result', () async {
      final source = _FakeSource(books: [const NovelBook(id: '1', title: 't1', author: '', intro: '', coverUrl: '', detailUrl: '')]);
      final cache = _FakeCache(namespace: 'test');
      final repo = NovelRepository(source: source, cache: cache);

      final first = await repo.searchBooks('a', page: 1);
      expect(first.length, 1);
      expect(source.searchCalls, 1);

      final second = await repo.searchBooks('a', page: 1);
      expect(second.length, 1);
      expect(source.searchCalls, 1);
    });

    test('searchBooks forceRefresh bypasses cache', () async {
      final source = _FakeSource(books: [const NovelBook(id: '1', title: 't1', author: '', intro: '', coverUrl: '', detailUrl: '')]);
      final cache = _FakeCache(map: {'search:a:1': [{'id': 'cached'}]}, namespace: 'test');
      final repo = NovelRepository(source: source, cache: cache);

      final result = await repo.searchBooks('a', page: 1, forceRefresh: true);
      expect(result.first.id, '1');
      expect(source.searchCalls, 1);
    });
  });
}

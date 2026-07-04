import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/novel/core/offline_book_info.dart';
import 'package:box/novel/core/offline_cache_service.dart';
import 'package:box/novel/core/cache_store.dart';
import 'package:box/novel/core/models.dart';
import 'package:box/novel/core/novel_repository.dart';
import 'package:box/novel/core/novel_source.dart';

/// 最小化 Fake 仓库 — 只 stub fetchDetail
class _FakeNovelRepository extends NovelRepository {
  _FakeNovelRepository()
      : super(
          source: _FakeNovelSource(),
          cache: CacheStore.inMemory('offline_test'),
        );
}

class _FakeNovelSource extends NovelSource {
  @override
  Future<List<NovelBook>> searchBooks(String keyword, {int page = 1}) async => [];

  @override
  Future<List<NovelBook>> fetchByPath(String path) async => [];

  @override
  Future<NovelDetail> fetchDetail({required String bookId, String? detailUrl}) async =>
      NovelDetail(
        book: NovelBook(
          id: bookId, title: '', author: '',
          intro: '', coverUrl: '', detailUrl: bookId,
        ),
        chapters: [],
      );

  @override
  Future<ChapterContent> fetchChapter({required NovelDetail detail, required int chapterIndex}) async =>
      ChapterContent(
        title: 'Ch',
        content: 'fake',
        chapterIndex: chapterIndex,
        sourceUrl: '',
        fromCache: false,
      );
}

void main() {
  group('OfflineCacheService metadata storage', () {
    late SharedPreferences prefs;
    late OfflineCacheService service;
    late CacheStore cacheStore;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      cacheStore = CacheStore.inMemory('offline_test');
      final repo = _FakeNovelRepository();
      service = OfflineCacheService(
        cache: cacheStore,
        repository: repo,
      );
    });

    test('markForOffline stores ID in set', () async {
      final detail = NovelDetail(
        book: NovelBook(
          id: 'b1',
          title: 'Test',
          author: 'Auth',
          intro: 'Intro',
          coverUrl: '',
          detailUrl: 'b1',
        ),
        chapters: [
          NovelChapter(title: 'Ch1', url: 'http://ex.com/1'),
          NovelChapter(title: 'Ch2', url: 'http://ex.com/2'),
        ],
      );

      await service.markForOffline(detail);

      final ids = await service.getOfflineBookIds();
      expect(ids, contains('b1'));
    });

    test('markForOffline stores metadata', () async {
      final detail = NovelDetail(
        book: NovelBook(
          id: 'b2',
          title: 'The Book',
          author: 'Writer',
          intro: 'Desc',
          coverUrl: 'http://ex.com/c.jpg',
          detailUrl: 'b2',
        ),
        chapters: [
          NovelChapter(title: 'Ch1', url: 'http://ex.com/1'),
          NovelChapter(title: 'Ch2', url: 'http://ex.com/2'),
        ],
      );

      await service.markForOffline(detail);

      final metas = await service.getOfflineMetas();
      expect(metas.length, 1);
      expect(metas[0].id, 'b2');
      expect(metas[0].title, 'The Book');
      expect(metas[0].author, 'Writer');
      expect(metas[0].coverUrl, 'http://ex.com/c.jpg');
      expect(metas[0].totalChapters, 2);
    });

    test('isMarkedOffline returns correct bool', () async {
      final detail = NovelDetail(
        book: NovelBook(
          id: 'b3',
          title: 'Book3',
          author: 'A',
          intro: '',
          coverUrl: '',
          detailUrl: 'b3',
        ),
        chapters: [],
      );

      expect(await service.isMarkedOffline('b3'), false);

      await service.markForOffline(detail);

      expect(await service.isMarkedOffline('b3'), true);
      expect(await service.isMarkedOffline('nonexistent'), false);
    });

    test('unmarkOffline removes ID and metadata', () async {
      final detail = NovelDetail(
        book: NovelBook(
          id: 'b4',
          title: 'Book4',
          author: 'A',
          intro: '',
          coverUrl: '',
          detailUrl: 'b4',
        ),
        chapters: [],
      );

      await service.markForOffline(detail);
      expect(await service.isMarkedOffline('b4'), true);

      await service.unmarkOfflineById('b4');
      expect(await service.isMarkedOffline('b4'), false);

      final metas = await service.getOfflineMetas();
      expect(metas.where((m) => m.id == 'b4'), isEmpty);
    });

    test('getOfflineMetas returns empty when nothing stored', () async {
      final metas = await service.getOfflineMetas();
      expect(metas, isEmpty);
    });

    test('filterOfflineBooks returns correct subset', () async {
      final detail = NovelDetail(
        book: NovelBook(
          id: 'b5',
          title: 'Book5',
          author: 'A',
          intro: '',
          coverUrl: '',
          detailUrl: 'b5',
        ),
        chapters: [],
      );

      await service.markForOffline(detail);

      final result = await service.filterOfflineBooks(['b5', 'b999', 'b888']);
      expect(result, contains('b5'));
      expect(result.length, 1);
    });

    test('getOfflineBookInfos returns infos with metadata', () async {
      final detail = NovelDetail(
        book: NovelBook(
          id: 'b6',
          title: 'Book6',
          author: 'A',
          intro: '',
          coverUrl: '',
          detailUrl: 'b6',
        ),
        chapters: [],
      );
      await service.markForOffline(detail);

      final infos = await service.getOfflineBookInfos();
      expect(infos.length, 1);
      expect(infos[0].id, 'b6');
      expect(infos[0].title, 'Book6');
    });

    test('clearAll removes all markers and metadata', () async {
      final detail = NovelDetail(
        book: NovelBook(
          id: 'b7',
          title: 'Book7',
          author: 'A',
          intro: '',
          coverUrl: '',
          detailUrl: 'b7',
        ),
        chapters: [],
      );
      await service.markForOffline(detail);
      expect(await service.getOfflineBookIds(), isNotEmpty);

      await service.clearAll();

      expect(await service.getOfflineBookIds(), isEmpty);
      expect(await service.getOfflineMetas(), isEmpty);
    });

    test('old format (Set<String>) is backward compatible', () async {
      await prefs.setStringList('offline_cached_books_v2', ['legacy1', 'legacy2']);

      final ids = await service.getOfflineBookIds();
      expect(ids, containsAll(['legacy1', 'legacy2']));
      expect(ids.length, 2);
    });

    test('metadata survives whole storage round-trip', () async {
      final detail = NovelDetail(
        book: NovelBook(
          id: 'b10',
          title: 'RoundTrip',
          author: 'Me',
          intro: '',
          coverUrl: 'http://ex.com/c.jpg',
          detailUrl: 'b10',
        ),
        chapters: [
          NovelChapter(title: 'C1', url: 'u1'),
        ],
      );
      await service.markForOffline(detail);

      final raw = prefs.getString('offline_books_meta_v3')!;
      final parsed = jsonDecode(raw) as List;
      expect(parsed.length, 1);
      expect((parsed[0] as Map)['id'], 'b10');
      expect((parsed[0] as Map)['title'], 'RoundTrip');
    });

    test('unmarkMultiple handles multiple books', () async {
      final details = [
        NovelDetail(
          book: NovelBook(
            id: 'm1', title: 'M1', author: 'A',
            intro: '', coverUrl: '', detailUrl: 'm1',
          ),
          chapters: [],
        ),
        NovelDetail(
          book: NovelBook(
            id: 'm2', title: 'M2', author: 'B',
            intro: '', coverUrl: '', detailUrl: 'm2',
          ),
          chapters: [],
        ),
      ];

      for (final d in details) {
        await service.markForOffline(d);
      }
      expect(await service.getOfflineBookIds(), containsAll(['m1', 'm2']));

      await service.unmarkMultiple(details);

      expect(await service.getOfflineBookIds(), isEmpty);
      final metas = await service.getOfflineMetas();
      expect(metas.where((m) => m.id == 'm1' || m.id == 'm2'), isEmpty);
    });
  });
}

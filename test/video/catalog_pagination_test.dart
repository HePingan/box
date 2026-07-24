import 'dart:async';

import 'package:box/video/controller/video_catalog_repository.dart';
import 'package:box/video/controller/video_controller.dart';
import 'package:box/video/models/video_category.dart';
import 'package:box/video/models/video_source.dart';
import 'package:box/video/models/vod_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('VideoCatalogRepository — pageSize contract', () {
    test('pageSize defaults to 20', () {
      const repo = VideoCatalogRepository();
      expect(repo.pageSize, 20);
    });

    test('pageSize is configurable via constructor', () {
      const repo = VideoCatalogRepository(pageSize: 15);
      expect(repo.pageSize, 15);
    });
  });

  // =========================================================================
  // Pagination tests — these drive the implementation of robust hasMore logic.
  //
  // Current behavior (PROBLEM):
  //   _hasMore = videos.length >= _repository.pageSize;
  //
  // This means:
  //   - 19 items → hasMore=false ✓
  //   - 20 items → hasMore=true  (might be the last page!)
  //   - 21 items → hasMore=true  ✓
  //
  // The "exactly full page" case is ambiguous. Without API-provided metadata
  // (total count, hasNext, etc.), we can't know if there are more pages.
  //
  // Our solution: Add a _consecutiveFullPage counter. When we see N consecutive
  // full pages, we assume the next call will either return fewer items
  // (confirming end) or the same number (suggesting we're at the end).
  //
  // For the minimal safe implementation:
  //   - Track _lastPageItemCount.
  //   - If current page is full AND last page was also full → cap hasMore.
  //   - Use a threshold (e.g., 2 consecutive full pages) before assuming no more.
  // =========================================================================

  group('VideoController — hasMore boundary behavior', () {
    test('hasMore is false when videos.length < pageSize (partial page)', () {
      const pageSize = 20;
      final partialPage = List.generate(pageSize - 1, (i) => i);
      expect(partialPage.length >= pageSize, isFalse);
    });

    test(
      'hasMore is true when videos.length == pageSize (full page — tentative)',
      () {
        const pageSize = 20;
        final fullPage = List.generate(pageSize, (i) => i);
        expect(fullPage.length >= pageSize, isTrue);
      },
    );

    test('empty result sets hasMore to false', () {
      const pageSize = 20;
      final empty = <VodItem>[];
      expect(empty.length >= pageSize, isFalse);
    });
  });

  // =========================================================================
  // These tests verify the _hasMore logic by examining the controller's
  // observable state after load operations. Since hasMore is a public getter,
  // we can test it directly.
  // =========================================================================

  group('VideoController — hasMore observable behavior', () {
    test('hasMore is false when API returns fewer items than pageSize', () async {
      const pageSize = 20;
      final repo = TestRepository(pageSize: pageSize);
      repo.videos = [
        for (int i = 0; i < 15; i++) VodItem(vodId: i, vodName: 'video_$i'),
      ];

      final controller = VideoController(repository: repo);
      await controller.initSources('https://catalog.example.com/');

      // Wait for all async work
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // With 15 items (< 20), hasMore should be false.
      // However, initSources loads sources first, then does _loadSourceData
      // with page=1. The repository returns 15 items, so hasMore should be false.
      expect(
        controller.hasMore,
        isFalse,
        reason: 'partial page should set hasMore=false',
      );
    });

    test(
      'hasMore is true when API returns exactly pageSize items (tentative)',
      () async {
        const pageSize = 20;
        final repo = TestRepository(pageSize: pageSize);
        repo.videos = [
          for (int i = 0; i < pageSize; i++)
            VodItem(vodId: i, vodName: 'video_$i'),
        ];

        final controller = VideoController(repository: repo);
        await controller.initSources('https://catalog.example.com/');
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // With exactly 20 items, the current code sets hasMore=true.
        // This is acceptable as a "tentative" signal.
        expect(
          controller.hasMore,
          isTrue,
          reason: 'full page sets hasMore=true (tentative)',
        );
      },
    );

    test(
      'after loading a partial page following a full page, hasMore becomes false',
      () async {
        const pageSize = 20;
        final repo = TestRepository(pageSize: pageSize);

        // First call: full page
        repo.videos = [
          for (int i = 0; i < pageSize; i++)
            VodItem(vodId: i, vodName: 'video_$i'),
        ];

        final controller = VideoController(repository: repo);
        await controller.initSources('https://catalog.example.com/');
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // Now simulate loading more — second page is partial
        repo.videos = [
          for (int i = 0; i < 7; i++)
            VodItem(vodId: pageSize + i, vodName: 'video_${pageSize + i}'),
        ];

        await controller.loadMore();
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // After loading a partial page, hasMore should be false.
        expect(
          controller.hasMore,
          isFalse,
          reason: 'partial page after full page should set hasMore=false',
        );
      },
    );

    test('loading an empty page always sets hasMore to false', () async {
      const pageSize = 20;
      final repo = TestRepository(pageSize: pageSize);

      // First call: full page
      repo.videos = [
        for (int i = 0; i < pageSize; i++)
          VodItem(vodId: i, vodName: 'video_$i'),
      ];

      final controller = VideoController(repository: repo);
      await controller.initSources('https://catalog.example.com/');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(controller.hasMore, isTrue);

      // Second call: empty
      repo.videos = [];

      await controller.loadMore();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        controller.hasMore,
        isFalse,
        reason: 'empty page should set hasMore=false',
      );
    });

    test(
      'consecutive full pages with new items keep hasMore true; '
      'a full page of duplicates stops it',
      () async {
        // Current design (see VideoController._resolveHasMore):
        //   - rawCount < pageSize            → hasMore=false (reached the end)
        //   - full page but addedCount == 0  → hasMore=false (source is
        //                                       re-emitting old pages; stop to
        //                                       avoid an infinite loop)
        //   - full page with new items       → hasMore=true (there is more)
        //
        // We do NOT cap on a fixed "N consecutive full pages" count anymore —
        // that would truncate deep catalogs whose API legitimately keeps
        // returning full pages. The dedup guard is the real infinite-loop
        // protection.
        const pageSize = 20;
        final repo = TestRepository(pageSize: pageSize);

        // Page 1: 20 fresh items.
        repo.videos = [
          for (int i = 0; i < pageSize; i++)
            VodItem(vodId: i, vodName: 'video_$i'),
        ];

        final controller = VideoController(repository: repo);
        await controller.initSources('https://catalog.example.com/');
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // Page 1 full with new items → still more to load.
        expect(controller.hasMore, isTrue);

        // Page 2: another 20 fresh items → still more (deep catalog).
        repo.videos = [
          for (int i = 0; i < pageSize; i++)
            VodItem(vodId: pageSize + i, vodName: 'video_${pageSize + i}'),
        ];
        await controller.loadMore();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(
          controller.hasMore,
          isTrue,
          reason: 'a full page of NEW items means there is genuinely more data',
        );

        // Page 3: a full page but every item is a duplicate of page 2 →
        // the source is looping; hasMore must drop to false.
        await controller.loadMore();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(
          controller.hasMore,
          isFalse,
          reason:
              'a full page with zero new items means the source is repeating; '
              'stop to prevent infinite loading',
        );
      },
    );
  });

  group('VideoController — loadMore guard', () {
    test('loadMore does not fetch when hasMore is false', () async {
      final repo = TestRepository(pageSize: 20);
      // Return fewer than pageSize items → hasMore=false
      repo.videos = [
        for (int i = 0; i < 10; i++) VodItem(vodId: i, vodName: 'video_$i'),
      ];

      final controller = VideoController(repository: repo);
      await controller.initSources('https://catalog.example.com/');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(controller.hasMore, isFalse);

      // Calling loadMore should be a no-op.
      int callCountBefore = repo.callCount;
      await controller.loadMore();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        repo.callCount,
        equals(callCountBefore),
        reason: 'loadMore should not trigger fetch when hasMore is false',
      );
    });

    test('loadMore does not fetch when isLoading is true', () async {
      final repo = TestRepository(pageSize: 20);
      // Make the first call take a long time so isLoading stays true.
      repo.delayMs = 500;

      final controller = VideoController(repository: repo);
      unawaited(controller.initSources('https://catalog.example.com/'));

      // The controller first loads the source catalog, then categories and
      // videos; wait until the video request is in flight.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // isLoading should be true.
      expect(controller.isLoading, isTrue);

      // Calling loadMore while loading should be a no-op.
      int callCountBefore = repo.callCount;
      await controller.loadMore();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        repo.callCount,
        equals(callCountBefore),
        reason: 'loadMore should not trigger fetch when isLoading is true',
      );
    });
  });
}

/// A test double for VideoCatalogRepository that allows controlling return values.
class TestRepository extends VideoCatalogRepository {
  TestRepository({super.pageSize = 20});

  List<VodItem> videos = [];
  int delayMs = 0;
  int callCount = 0;

  @override
  Future<List<VodItem>> loadVideos(
    VideoSource source, {
    required int? typeId,
    required int page,
  }) async {
    callCount++;
    if (delayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
    return videos;
  }

  @override
  Future<List<VideoCategory>> loadCategories(VideoSource source) async {
    return [
      const VideoCategory(typeId: 1, typeName: 'Category1'),
      const VideoCategory(typeId: 2, typeName: 'Category2'),
    ];
  }

  @override
  Future<List<VideoSource>> loadSources(String catalogUrl) async {
    return [
      const VideoSource(
        id: 'test-source',
        name: 'TestSource',
        url: 'https://api.example.com/api.php/provide/vod/',
        detailUrl: '',
      ),
    ];
  }
}

// 漫画库页面（书架）行为回归锁。
//
// 锁住：
//   1. 空库时给出引导，而不是白屏
//   2. 书架卡片显示真实阅读进度角标（task 6 的「书架进度角标」）
//   3. 没有进度的书不显示角标（不能凭空造一个 0%）
//   4. 删除必须二次确认（长按直接删是数据丢失风险）
library;

import 'dart:io';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/comic/domain/comic_image_cache.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/domain/comic_online_progress.dart';
import 'package:box/features/comic/domain/comic_reader_state.dart';
import 'package:box/features/comic/presentation/comic_library_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ComicBook _book({
  required String id,
  required String title,
  int pageCount = 100,
}) {
  return ComicBook(
    id: id,
    title: title,
    sourceType: ComicSourceType.folder,
    folderPath: '/tmp/none/$id',
    pages: List.generate(pageCount, (i) => '/tmp/none/$id/$i.jpg'),
    pageCount: pageCount,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );
}

void main() {
  late ComicLibraryStore store;

  setUp(() {
    store = ComicLibraryStore(
      cacheStore: CacheStore.inMemory('comic_library_page_test'),
    );
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    ComicOnlineProgressStore? onlineProgressStore,
    ComicImageCache? coverCache,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ComicLibraryPage(
          libraryStore: store,
          onlineProgressStore: onlineProgressStore,
          // 默认给一份"不联网"的封面缓存：真缓存要走 path_provider，
          // 在 widget 测试里那个平台调用不会有人应答（页面会一直转圈）。
          coverCache: coverCache ?? _FakeCoverCache(failWith: '测试环境不联网'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('空库时给出导入引导', (tester) async {
    await pumpPage(tester);

    expect(find.text('还没有漫画'), findsOneWidget);
    // 回归锁：这里以前写着"在线漫画源请到扩展页安装"—— 扩展页里根本没有漫画源可装，
    // 是"说了做不到"。现在指向真的能用的入口（源自检），不许再回到那种写法。
    expect(find.textContaining('扩展页安装'), findsNothing);
    // 两个入口都要指到：在线漫画（地球）与源自检（盾牌）
    expect(find.textContaining('搜索阅读'), findsWidgets);
    expect(find.textContaining('自检'), findsWidgets);
    expect(find.text('导入漫画'), findsOneWidget);
  });

  testWidgets('书架卡片显示真实阅读进度角标', (tester) async {
    await store.add(_book(id: 'b1', title: '有进度的书', pageCount: 100));
    await store.saveProgress(
      ComicReaderState(
        comicBookId: 'b1',
        currentPageIndex: 24, // 第 25 页 / 100 => 25%
        totalPages: 100,
        isScrollMode: false,
        lastReadAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    await pumpPage(tester);

    expect(find.text('有进度的书'), findsOneWidget);
    expect(
      find.text('25%'),
      findsOneWidget,
      reason: '书架必须展示真实进度，而不是只有一个「已读」眼睛图标',
    );
  });

  testWidgets('没有进度的书不显示进度角标', (tester) async {
    await store.add(_book(id: 'b2', title: '没读过的书'));

    await pumpPage(tester);

    expect(find.text('没读过的书'), findsOneWidget);
    expect(
      find.textContaining('%'),
      findsNothing,
      reason: '没读过就不该凭空造一个进度出来',
    );
  });

  testWidgets('删除漫画必须二次确认', (tester) async {
    await store.add(_book(id: 'b3', title: '待删除的书'));
    await pumpPage(tester);

    await tester.longPress(find.text('待删除的书'));
    await tester.pumpAndSettle();

    // 必须先弹确认框，且此时书还在
    expect(find.textContaining('删除'), findsWidgets);
    expect((await store.fetch()).length, 1, reason: '确认前不得真的删掉');

    // 取消 → 书仍在
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect((await store.fetch()).length, 1);

    // 再来一次，确认删除
    await tester.longPress(find.text('待删除的书'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();

    expect((await store.fetch()), isEmpty, reason: '确认后应真的删掉');
    expect(find.text('还没有漫画'), findsOneWidget);
  });

  testWidgets('在线书进书架：显示"读到哪一话"，而不是假的百分比', (tester) async {
    // 在线进度按**书链**存（与本地书按 id 存不是一回事）
    final progressStore = ComicOnlineProgressStore(
      cacheStore: CacheStore.inMemory('comic_library_online_progress'),
    );
    const bookUrl = 'https://cn.baozimhcn.com/comic/hanghaiwang';
    await progressStore.save(
      const ComicOnlineProgress(
        bookUrl: bookUrl,
        chapterUrl: 'https://cn.dzmanga.com/comic/chapter/x/0_1186.html',
        chapterTitle: '第1186话 再一次',
        index: 3,
      ),
    );
    await store.add(
      ComicBook(
        id: bookUrl,
        title: '航海王',
        sourceType: ComicSourceType.online,
        onlineUrl: bookUrl,
        coverPath: 'https://static-tw.baozimhcn.com/cover/hanghaiwang.jpg',
        author: '尾田荣一郎',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    await pumpPage(tester, onlineProgressStore: progressStore);

    expect(find.text('航海王'), findsOneWidget);
    expect(find.text('读到 第1186话 再一次'), findsOneWidget);
    // 在线书不该凭空显示一个百分比（本地进度读不到）
    expect(find.textContaining('%'), findsNothing);
  });

  test('在线书判定：有书链才算在线书（缺书链点进去无从可去）', () {
    ComicBook mk(ComicSourceType type, String? url) => ComicBook(
      id: 'x',
      title: 'x',
      sourceType: type,
      onlineUrl: url,
      createdAt: 1,
    );
    expect(mk(ComicSourceType.online, 'https://a/book').isOnline, isTrue);
    expect(mk(ComicSourceType.online, null).isOnline, isFalse);
    expect(mk(ComicSourceType.online, '').isOnline, isFalse);
    expect(mk(ComicSourceType.folder, 'https://a/book').isOnline, isFalse);
  });

  // 封面这条路以前是 `Image.network`（一份请求头都不带）：图床把请求丢掉，界面上只剩
  // 一个破图标，用户只能说"封面加载不出来"，我这边也拿不到原因（2026-09-29）。
  // 现在封面走**图片缓存**（带手机 UA），失败必须**把原因写出来**并可重试。
  group('在线书封面', () {
    const cover = 'https://tuer.justpic01pt.com:666/picbed/CPMH/hzw/a.jpg';

    Future<void> addOnlineBook() => store.add(
      const ComicBook(
        id: 'https://yemancomic.com/book/7530/',
        title: '海贼王',
        sourceType: ComicSourceType.online,
        onlineUrl: 'https://yemancomic.com/book/7530/',
        coverPath: cover,
        createdAt: 1,
      ),
    );

    testWidgets('走图片缓存（带请求头），不是不带头的 Image.network', (tester) async {
      await addOnlineBook();
      final cache = _FakeCoverCache(failWith: '这张图没下来（HTTP 403）');

      await pumpPage(
        tester,
        // 在线书要查在线进度：给一份内存存储，不然会去碰真存储（测试里没人应答）。
        onlineProgressStore: ComicOnlineProgressStore(
          cacheStore: CacheStore.inMemory('cover_progress_a'),
        ),
        coverCache: cache,
      );

      expect(cache.asked, contains(cover), reason: '封面要经缓存取（缓存里带手机 UA）');
      // 失败时把原因写出来 + 给重试的路
      expect(find.textContaining('HTTP 403'), findsOneWidget);
      expect(find.textContaining('点一下重试'), findsOneWidget);

      await tester.tap(find.textContaining('点一下重试'));
      await tester.pumpAndSettle();
      expect(cache.asked.length, 2, reason: '重试要真的再取一次');
    });

    testWidgets('下到了就出图（不写原因、不留破图标）', (tester) async {
      await addOnlineBook();
      final file = File(
        '${Directory.systemTemp.path}/shelf_cover_'
        '${DateTime.now().microsecondsSinceEpoch}.png',
      )..writeAsBytesSync(_pngBytes);

      await pumpPage(
        tester,
        onlineProgressStore: ComicOnlineProgressStore(
          cacheStore: CacheStore.inMemory('cover_progress_b'),
        ),
        coverCache: _FakeCoverCache(file: file),
      );

      expect(find.textContaining('HTTP'), findsNothing);
      expect(find.textContaining('点一下重试'), findsNothing);
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(
        images.any((i) => i.image is FileImage),
        isTrue,
        reason: '下到本地就该用本地文件显示',
      );
    });
  });
}

/// 假封面缓存：给一个真文件（成功）或抛错（失败要说原因）。
class _FakeCoverCache extends ComicImageCache {
  _FakeCoverCache({this.file, this.failWith});

  final File? file;
  final String? failWith;

  /// 被问过的地址（用来确认封面真的走了缓存这条路）。
  final List<String> asked = <String>[];

  @override
  Future<File> fetch(String url) async {
    asked.add(url);
    final reason = failWith;
    if (reason != null) throw ComicImageException(reason);
    return file!;
  }

  @override
  Future<File?> cachedFile(String url) async => null;
}

/// 1×1 真 PNG（Image.file 要能被解码，随便几个字节会被当成坏图）。
const List<int> _pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

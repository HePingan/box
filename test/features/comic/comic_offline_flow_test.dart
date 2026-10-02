// 离线下载的界面底线（**不做真磁盘 IO**：假时钟下真 IO 的 Future 不会完成，会把测试挂死）：
//   ① 站点打不开时，详情页要从离线清单把**已下载的话**列出来（下过了却连目录都进不去最不像话）
//   ② 目录每条右边那个下载控件：点一下真的入队并下到本机
//   ③ 管理页：列出来、能看到占用、能删
//
// 分工：磁盘/清单本身的行为（先写临时再改名、删一话清零、坏清单不炸…）由
// `comic_offline_store_test.dart` 用**真临时目录**覆盖；下载队列的时序由
// `comic_offline_downloader_test.dart` 用**真 HTTP 服务器**覆盖。这里只看界面。
library;

import 'dart:io';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_image_cache.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/domain/comic_offline_downloader.dart';
import 'package:box/features/comic/domain/comic_offline_store.dart';
import 'package:box/features/comic/domain/comic_online_progress.dart';
import 'package:box/features/comic/domain/comic_reader_prefs.dart';
import 'package:box/features/comic/domain/comic_source.dart';
import 'package:box/features/comic/domain/sources/seed_comic_source.dart';
import 'package:box/features/comic/presentation/comic_offline_page.dart';
import 'package:box/features/comic/presentation/comic_online_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_comic_target.dart';

const String _bookUrl = 'https://yemancomic.com/comic/haizeiwang';
const String _chapterUrl = 'https://yemancomic.com/comic/page_1/1186.html';
const String _img1 = 'https://tupian.justpic01pt.com:666/picbed/1.jpg';
const String _img2 = 'https://tupian.justpic01pt.com:666/picbed/2.jpg';
const String _cover = 'https://tupian.justpic01pt.com:666/picbed/cover.jpg';

/// 内存版离线库（界面只认"清单里有没有"和"文件在不在"这两件事）。
class _FakeOfflineStore extends ComicOfflineStore {
  _FakeOfflineStore(this.root);

  final Directory root;
  final Map<String, ComicOfflineBook> saved = <String, ComicOfflineBook>{};

  /// 界面问"本机有没有"时看的根：真去这个临时目录同步看一眼（不涉及假时钟）。
  @override
  Directory? get readyRoot => root;

  @override
  Future<void> warmUp() async {}

  @override
  Future<ComicOfflineBook?> loadBook(String bookUrl) async => saved[bookUrl];

  @override
  Future<void> saveBook(ComicOfflineBook book) async => saved[book.bookUrl] = book;

  @override
  Future<List<ComicOfflineBook>> books() async => saved.values.toList();

  @override
  Future<int> totalBytes() async =>
      saved.values.fold<int>(0, (a, b) => a + b.bytes);

  @override
  Future<int> bytesOf(String bookUrl, {String? chapterUrl}) async =>
      saved[bookUrl]?.bytes ?? 0;

  @override
  Future<void> deleteBook(String bookUrl) async => saved.remove(bookUrl);

  @override
  Future<void> deleteChapter(String bookUrl, String chapterUrl) async {
    final book = saved[bookUrl];
    if (book == null) return;
    book.chapters.removeWhere((c) => c.url == chapterUrl);
    if (book.chapters.isEmpty) saved.remove(bookUrl);
  }

  String pathFor(String imageUrl) =>
      '${root.path}/img/${ComicOfflineStore.hash(imageUrl)}';

  @override
  Future<File> fileFor(String bookUrl, String chapterUrl, String imageUrl) async =>
      File(pathFor(imageUrl));

  @override
  File? localFileIfReady(String bookUrl, String chapterUrl, String imageUrl) {
    final f = File(pathFor(imageUrl));
    return f.existsSync() ? f : null;
  }

  @override
  Future<File?> localFile(String bookUrl, String chapterUrl, String imageUrl) async =>
      localFileIfReady(bookUrl, chapterUrl, imageUrl);

  @override
  Future<File?> localCover(String bookUrl, String coverUrl) async => null;
}

/// 假缓存：给 `dest` 就真写进去（离线下载要验"文件在不在"，只返回值不够）。
class _FakeCache extends ComicImageCache {
  final List<String> asked = <String>[];

  @override
  Future<File> fetch(String url, {bool lowPriority = false, File? dest}) async {
    asked.add(url);
    final f = dest ?? File('/dev/null');
    if (dest != null) {
      await dest.writeAsBytes(List<int>.filled(64, 7));
    }
    return f;
  }
}

ComicSource _seed() => ComicSource.tryParse(kSeedComicSourceJson)!;

void main() {
  late Directory root;
  late _FakeOfflineStore store;
  late _FakeCache cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('offline_flow_');
    store = _FakeOfflineStore(root);
    cache = _FakeCache();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// 造一本"已经下好一话"的清单（断网兜底用的现场）+ 两个真的图片文件。
  void seedDownloaded() {
    store.saved[_bookUrl] = ComicOfflineBook(
      bookUrl: _bookUrl,
      title: '航海王',
      cover: _cover,
      chapters: [
        ComicOfflineChapter(
          url: _chapterUrl,
          title: '第1186话',
          images: [_img1, _img2],
          done: 2,
          bytes: 4096,
          state: ComicOfflineState.done,
        ),
      ],
    );
    final imgDir = Directory('${root.path}/img')..createSync(recursive: true);
    for (final u in [_img1, _img2]) {
      File('${imgDir.path}/${ComicOfflineStore.hash(u)}')
          .writeAsBytesSync(List<int>.filled(2048, 3));
    }
  }

  /// 打开漫画页（注入离线库、假缓存、内存书架/进度/偏好）。
  Widget page(FakeComicTarget target, {ComicOfflineDownloader? downloader}) =>
      MaterialApp(
        home: ComicOnlinePage(
          source: _seed(),
          targetBuilder: () => target,
          imageCache: cache,
          offlineStore: store,
          offlineDownloader: downloader,
          initialBookUrl: _bookUrl,
          relayToken: '',
          waitTimeout: const Duration(milliseconds: 20),
          listTimeout: const Duration(milliseconds: 20),
          openTimeout: const Duration(milliseconds: 20),
          libraryStore: ComicLibraryStore(
            cacheStore: CacheStore.inMemory('offline_flow_shelf'),
          ),
          progressStore: ComicOnlineProgressStore(
            cacheStore: CacheStore.inMemory('offline_flow_progress'),
          ),
          readerPrefs: ComicReaderPrefs(
            cacheStore: CacheStore.inMemory('offline_flow_prefs'),
          ),
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  testWidgets('站点打不开：详情页从离线清单列出已下载的话（不是一片报错）', (tester) async {
    seedDownloaded();

    // 搜索能出卡，但没有目录容器 → 详情取不到（模拟断网/站点挂了）。
    final source = _seed();
    final card = source.searchRules['bookList']!;
    final target = FakeComicTarget(
      counts: {card: 1},
      perElement: {
        '$card|${source.searchRules['name']}': ['航海王'],
        '$card|${source.searchRules['bookUrl']}': ['/comic/haizeiwang'],
      },
      values: {source.bookInfoRules['name']!: ['航海王']},
      jsSegment: '',
    );

    await tester.pumpWidget(page(target));
    await settle(tester);

    expect(find.textContaining('离线模式'), findsOneWidget);
    expect(find.text('航海王'), findsWidgets, reason: '书名来自离线清单');
    expect(find.text('第1186话'), findsOneWidget, reason: '已下载的那一话要能点进去');
  });

  testWidgets('点目录右边的下载控件：这一话真的进了下载队列', (tester) async {
    // 目录里有一话，但本机还没下过。
    final source = _seed();
    final card = source.searchRules['bookList']!;
    final tocRule = source.bookInfoRules['tocUrl']!;
    final container = firstSelectorRule(tocRule)!;
    final target = FakeComicTarget(
      counts: {card: 1, container: 1},
      perElement: {
        '$card|${source.searchRules['name']}': ['航海王'],
        '$card|${source.searchRules['bookUrl']}': ['/comic/haizeiwang'],
        '$container|${source.tocRules['chapterName']}': ['第1186话'],
        '$container|${source.tocRules['chapterUrl']}': [
          '/user/page_direct?slot=1186',
        ],
      },
      values: {source.bookInfoRules['name']!: ['航海王']},
      jsSegment: '',
    );

    final dl = ComicOfflineDownloader(
      store: store,
      cache: cache,
      loadImages: (chapterUrl) async => [_img1, _img2],
      networkAllowed: () async => true,
    );

    await tester.pumpWidget(page(target, downloader: dl));
    // 页面自己会把队列的"取图地址"接成**服务那条路**（生产就该这样）；测试里没有
    // 站点那套取图规则，所以建完页再换回假的 —— 这里验的是"按下控件之后队列里有没有这一话"。
    dl.setLoadImages((chapterUrl) async => [_img1, _img2]);
    // 页面 initState 还会装"仅 Wi-Fi"策略（生产必须装），那要走平台通道读设置 +
    // 问网络类型；测试里没有平台实现，所以这里换回"一律放行"，专门验控件→队列这一段。
    dl.setNetworkAllowed(() async => true);
    await settle(tester);
    expect(find.text('第1186话'), findsOneWidget);
    expect(find.byTooltip('下载这一话'), findsOneWidget);

    await tester.tap(find.byType(ChapterOfflineAction));
    await settle(tester);

    expect(dl.jobs.length, 1, reason: '按一下就该进队列');
    expect(dl.jobs.single.chapterTitle, '第1186话');
    expect(dl.jobs.single.total, 2, reason: '这一话的图片地址已经取到了');
    expect(
      dl.jobs.single.state == ComicOfflineJobState.running ||
          dl.jobs.single.state == ComicOfflineJobState.done,
      isTrue,
    );
    expect(find.byTooltip('下载这一话'), findsNothing, reason: '已经不是"未下载"态了');

    // 真正"下到本机"那一段（落盘、续传、失败重试）在
    // comic_offline_downloader_test.dart 里用真 HTTP 服务器验：widget 测试跑在
    // 假时钟下，真磁盘 IO 的续体不归它管，硬在这里验会把用例变成"看运气"。
  });

  testWidgets('点「下载 → 整本」：正在看的这一话排在最前面', (tester) async {
    // 三话的书，进来先读第 2 话，然后选「整本」。
    final source = _seed();
    final card = source.searchRules['bookList']!;
    final container = firstSelectorRule(source.bookInfoRules['tocUrl']!)!;
    final target = FakeComicTarget(
      counts: {card: 1, container: 3},
      perElement: {
        '$card|${source.searchRules['name']}': ['航海王'],
        '$card|${source.searchRules['bookUrl']}': ['/comic/haizeiwang'],
        '$container|${source.tocRules['chapterName']}': ['第1话', '第2话', '第3话'],
        '$container|${source.tocRules['chapterUrl']}': [
          '/user/page_direct?slot=11',
          '/user/page_direct?slot=22',
          '/user/page_direct?slot=33',
        ],
      },
      values: {source.bookInfoRules['name']!: ['航海王']},
      jsSegment: '<img src="https://s1.bzcdn.net/a/1.jpg">',
    );

    final dl = ComicOfflineDownloader(
      store: store,
      cache: cache,
      loadImages: (chapterUrl) async => [_img1],
      networkAllowed: () async => true,
    );

    await tester.pumpWidget(page(target, downloader: dl));
    dl.setLoadImages((chapterUrl) async => [_img1]);
    dl.setNetworkAllowed(() async => true);
    await settle(tester);

    // 读第 2 话（"正在看的这一话"）
    await tester.tap(find.text('第2话'));
    await settle(tester);

    // 回到详情页点「下载」→ 选整本
    await tester.tap(find.byIcon(Icons.arrow_back));
    await settle(tester);
    await tester.tap(find.text('下载'));
    await settle(tester);
    await tester.tap(find.textContaining('整本').last);
    await settle(tester);

    expect(dl.jobs.length, 3, reason: '整本=三话都排队');
    expect(
      dl.jobs.first.chapterTitle,
      '第2话',
      reason: '正在看的那一话要排最前（不然要等前面几十话下完）',
    );
  });

  testWidgets('管理页：列出来、显示占用、能删整本', (tester) async {
    seedDownloaded();
    final dl = ComicOfflineDownloader(store: store, cache: cache);

    await tester.pumpWidget(
      MaterialApp(home: ComicOfflinePage(store: store, downloader: dl)),
    );
    await settle(tester);

    expect(find.text('航海王'), findsOneWidget);
    expect(find.textContaining('已下载 1/1 话'), findsOneWidget);
    expect(find.textContaining('离线内容共'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await settle(tester);
    await tester.tap(find.text('删除'));
    await settle(tester);

    expect(find.text('航海王'), findsNothing);
    expect(find.textContaining('还没有下载过漫画'), findsOneWidget);
    expect(store.saved, isEmpty);
  });
}

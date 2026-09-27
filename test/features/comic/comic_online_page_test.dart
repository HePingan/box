// 在线页面：搜索 → 详情/目录 → 阅读 三态切换的界面用例。
//
// 用假取数 + 假图片缓存：不联网、不起 WebView、不读系统目录。
// 三条底线各有一条用例：结果能点进去 / 失败说人话 / 取不到图时不假装成功。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_image_cache.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/domain/comic_online_progress.dart';
import 'package:box/features/comic/domain/comic_reader_prefs.dart';
import 'package:box/features/comic/domain/comic_source.dart';
import 'package:box/features/comic/domain/sources/seed_comic_source.dart';
import 'package:box/features/comic/presentation/comic_online_page.dart';

import 'fake_comic_target.dart';

/// 1×1 的透明 PNG（够 Image.file 解码）。
const List<int> _pngBytes = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// 假图片缓存：直接给一个真 PNG 文件（不下载）。
class _FakeCache extends ComicImageCache {
  _FakeCache(this.file);

  final File file;

  @override
  Future<File> fetch(String url) async => file;

  @override
  Future<File?> cachedFile(String url) async => file;
}

ComicSource _seed() => ComicSource.tryParse(kSeedComicSourceJson)!;

/// 造一个上传好假数据的页面。
Widget _page(
  FakeComicTarget target,
  _FakeCache cache, {
  ComicLibraryStore? libraryStore,
  ComicOnlineProgressStore? progressStore,
  ComicReaderPrefs? readerPrefs,
  String? initialBookUrl,
}) {
  return MaterialApp(
    home: ComicOnlinePage(
      source: _seed(),
      targetBuilder: () => target,
      imageCache: cache,
      waitTimeout: const Duration(milliseconds: 20),
      listTimeout: const Duration(milliseconds: 20),
      openTimeout: const Duration(milliseconds: 20),
      libraryStore:
          libraryStore ??
          ComicLibraryStore(
            cacheStore: CacheStore.inMemory('online_page_shelf_default'),
          ),
      readerPrefs:
          readerPrefs ??
          ComicReaderPrefs(
            cacheStore: CacheStore.inMemory('online_page_prefs_default'),
          ),
      initialBookUrl: initialBookUrl,
      progressStore:
          progressStore ??
          ComicOnlineProgressStore(
            cacheStore: CacheStore.inMemory('online_page_test'),
          ),
    ),
  );
}

/// 推够时间：假取数是一串 await，单次 pump 不一定够。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  late File png;

  setUp(() async {
    final dir = Directory.systemTemp.createTempSync('online_page_test');
    png = File('${dir.path}/x.png')..writeAsBytesSync(_pngBytes);
  });

  testWidgets('搜索 → 详情 → 阅读：三态都能走通', (tester) async {
    final source = _seed();
    final card = source.searchRules['bookList']!;
    final tocRule = source.bookInfoRules['tocUrl']!;
    final container = firstSelectorRule(tocRule)!;

    final target = FakeComicTarget(
      counts: {card: 1, container: 1},
      perElement: {
        '$card|${source.searchRules['name']}': ['海贼王'],
        '$card|${source.searchRules['bookUrl']}': ['/comic/haizeiwang'],
        '$card|${source.searchRules['author']}': ['尾田荣一郎'],
        '$container|${source.tocRules['chapterName']}': ['第1186话'],
        '$container|${source.tocRules['chapterUrl']}': ['/user/page_direct?slot=1186'],
      },
      values: {
        source.bookInfoRules['name']!: ['航海王'],
        source.bookInfoRules['author']!: ['尾田荣一郎'],
      },
      jsSegment: '<img src="https://s1.bzcdn.net/a/1.jpg">',
    );

    await tester.pumpWidget(_page(target, _FakeCache(png)));

    // ① 搜索
    await tester.enterText(find.byType(TextField), '海贼');
    await tester.tap(find.text('搜索'));
    await _settle(tester);
    expect(find.text('海贼王'), findsOneWidget);
    expect(find.text('尾田荣一郎'), findsOneWidget);

    // ② 点进详情：书名 + 目录
    await tester.tap(find.text('海贼王'));
    await _settle(tester);
    expect(find.text('航海王'), findsWidgets);
    expect(find.text('共 1 话'), findsOneWidget);
    expect(find.text('第1186话'), findsOneWidget);

    // ③ 点章节 → 阅读器：张数如实显示
    await tester.tap(find.text('第1186话'));
    await _settle(tester);
    expect(find.text('1 / 1 张'), findsOneWidget);
    // 目录只有一话，前后都没有 → 两个按钮都该是禁用的（不假装能翻）
    final buttons = tester
        .widgetList<TextButton>(find.byType(TextButton))
        .toList();
    expect(buttons.where((b) => b.onPressed == null).length, 2);
  });

  testWidgets('搜不到就说清原因，不显示成"没有结果"', (tester) async {
    final source = _seed();
    final card = source.searchRules['bookList']!;
    final target = FakeComicTarget(
      counts: {card: 1},
      perElement: {
        '$card|${source.searchRules['name']}': ['甲'],
        '$card|${source.searchRules['bookUrl']}': [''],
      },
    );

    await tester.pumpWidget(_page(target, _FakeCache(png)));
    await tester.enterText(find.byType(TextField), 'x');
    await tester.tap(find.text('搜索'));
    await _settle(tester);

    expect(find.textContaining('书链一条都没取到'), findsOneWidget);
  });

  testWidgets('这一话没取到图：如实说，且给返回的路（不假装成功）', (tester) async {
    final source = _seed();
    final card = source.searchRules['bookList']!;
    final tocRule = source.bookInfoRules['tocUrl']!;
    final container = firstSelectorRule(tocRule)!;

    final target = FakeComicTarget(
      counts: {card: 1, container: 1},
      perElement: {
        '$card|${source.searchRules['name']}': ['海贼王'],
        '$card|${source.searchRules['bookUrl']}': ['/comic/haizeiwang'],
        '$container|${source.tocRules['chapterName']}': ['第1186话'],
        '$container|${source.tocRules['chapterUrl']}': ['/user/page_direct?slot=1186'],
      },
      values: {source.bookInfoRules['name']!: ['航海王']},
      jsSegment: '',
    );

    await tester.pumpWidget(
      _page(
        target,
        _FakeCache(png),
        progressStore: ComicOnlineProgressStore(
          cacheStore: CacheStore.inMemory('online_page_test2'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '海贼');
    await tester.tap(find.text('搜索'));
    await _settle(tester);
    await tester.tap(find.text('海贼王'));
    await _settle(tester);
    await tester.tap(find.text('第1186话'));
    await _settle(tester);

    expect(find.textContaining('一个图地址都没有'), findsWidgets);
  });

  testWidgets('分类浏览：顶部列出分类，点一下按分类出书（不用打字）', (tester) async {
    final cats = [
      {'title': '全部', 'url': 'https://cn.baozimhcn.com/api/list?type=all&page={{page}}'},
      {'title': '恋爱', 'url': 'https://cn.baozimhcn.com/api/list?type=lianai&page={{page}}'},
    ];
    const allUrl = 'https://cn.baozimhcn.com/api/list?type=all&page=1';
    final target = FakeComicTarget(
      // exploreUrl 的 JS 段 → 分类列表
      jsSegment: jsonEncode(cats),
      responses: {
        allUrl: jsonEncode({
          'items': [
            {'comic_id': 'hanghaiwang', 'name': '航海王', 'author': '尾田荣一郎'},
            {'comic_id': 'zuqiumaomao', 'name': '足球猫猫'},
          ],
        }),
      },
    );
    final png = File('${Directory.systemTemp.path}/comic_online_cat_${DateTime.now().microsecondsSinceEpoch}.png')
      ..writeAsBytesSync(_pngBytes);

    await tester.pumpWidget(_page(target, _FakeCache(png)));
    await _settle(tester);

    // 分类条出来了（书源给多少显示多少）
    expect(find.text('全部'), findsWidgets);
    expect(find.text('恋爱'), findsWidgets);
    expect(find.textContaining('或点上面的分类翻榜单'), findsOneWidget);

    await tester.tap(find.text('全部'));
    await _settle(tester);

    expect(find.text('航海王'), findsOneWidget);
    expect(find.text('足球猫猫'), findsOneWidget);
    // 响应里没给 next → 不显示「加载更多」（不假装还有）
    expect(find.text('加载更多'), findsNothing);
    // 取数的地址是分类地址，而且是**在页面里发请求**（不走打开页面）
    expect(target.fetched, contains(allUrl));
    expect(target.opened, isNot(contains(allUrl)));
  });

  testWidgets('从书架点进来：直接打开这本书（不用再搜一次）', (tester) async {
    final source = _seed();
    final card = source.searchRules['bookList']!;
    final container = firstSelectorRule(source.bookInfoRules['tocUrl']!)!;
    final target = FakeComicTarget(
      counts: {card: 1, container: 1},
      perElement: {
        '$card|${source.searchRules['name']}': ['海贼王'],
        '$card|${source.searchRules['bookUrl']}': ['/comic/haizeiwang'],
        '$container|${source.tocRules['chapterName']}': ['第1186话'],
        '$container|${source.tocRules['chapterUrl']}': ['/c/1186'],
      },
      values: {
        source.bookInfoRules['name']!: ['航海王'],
        source.bookInfoRules['author']!: ['尾田荣一郎'],
      },
    );
    final png = File('${Directory.systemTemp.path}/comic_online_init_${DateTime.now().microsecondsSinceEpoch}.png')
      ..writeAsBytesSync(_pngBytes);

    await tester.pumpWidget(
      _page(
        target,
        _FakeCache(png),
        initialBookUrl: 'https://cn.baozimhcn.com/comic/haizeiwang',
      ),
    );
    await _settle(tester);

    expect(find.text('航海王'), findsWidgets);
    expect(find.text('共 1 话'), findsOneWidget);
    // 直接打开，没有经过搜索列表
    expect(find.text('搜索'), findsNothing);
  });

  testWidgets('加入书架：点了之后变成「已在书架」，并真的落进书架存储', (tester) async {
    final source = _seed();
    final card = source.searchRules['bookList']!;
    final container = firstSelectorRule(source.bookInfoRules['tocUrl']!)!;
    final target = FakeComicTarget(
      counts: {card: 1, container: 1},
      perElement: {
        '$card|${source.searchRules['name']}': ['海贼王'],
        '$card|${source.searchRules['bookUrl']}': ['/comic/haizeiwang'],
        '$card|${source.searchRules['author']}': ['尾田荣一郎'],
        '$container|${source.tocRules['chapterName']}': ['第1186话'],
        '$container|${source.tocRules['chapterUrl']}': ['/c/1186'],
      },
      values: {
        source.bookInfoRules['name']!: ['航海王'],
        source.bookInfoRules['author']!: ['尾田荣一郎'],
      },
    );
    final lib = ComicLibraryStore(
      cacheStore: CacheStore.inMemory('online_page_shelf'),
    );
    final png = File('${Directory.systemTemp.path}/comic_online_shelf_${DateTime.now().microsecondsSinceEpoch}.png')
      ..writeAsBytesSync(_pngBytes);

    await tester.pumpWidget(_page(target, _FakeCache(png), libraryStore: lib));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, '海贼');
    await tester.tap(find.text('搜索'));
    await _settle(tester);
    await tester.tap(find.text('海贼王'));
    await _settle(tester);

    expect(find.text('加入书架'), findsOneWidget);
    await tester.tap(find.text('加入书架'));
    await _settle(tester);

    expect(find.text('已在书架'), findsOneWidget);
    final books = await lib.fetch();
    expect(books.length, 1);
    expect(books.single.title, '航海王');
    expect(books.single.onlineUrl, 'https://cn.baozimhcn.com/comic/haizeiwang');
    expect(books.single.isOnline, isTrue);
  });

  testWidgets('有阅读进度时给「继续看 <那一话>」（没有就不显示）', (tester) async {
    final source = _seed();
    final card = source.searchRules['bookList']!;
    final container = firstSelectorRule(source.bookInfoRules['tocUrl']!)!;
    const bookUrl = 'https://cn.baozimhcn.com/comic/haizeiwang';
    final target = FakeComicTarget(
      counts: {card: 1, container: 1},
      perElement: {
        '$card|${source.searchRules['name']}': ['海贼王'],
        '$card|${source.searchRules['bookUrl']}': ['/comic/haizeiwang'],
        '$container|${source.tocRules['chapterName']}': ['第1186话'],
        '$container|${source.tocRules['chapterUrl']}': ['/c/1186'],
      },
      values: {
        source.bookInfoRules['name']!: ['航海王'],
        source.bookInfoRules['author']!: ['尾田荣一郎'],
      },
    );
    final progress = ComicOnlineProgressStore(
      cacheStore: CacheStore.inMemory('online_page_resume'),
    );
    await progress.save(
      const ComicOnlineProgress(
        bookUrl: bookUrl,
        chapterUrl: 'https://cn.baozimhcn.com/c/1186',
        chapterTitle: '第1186话',
        index: 2,
      ),
    );
    final png = File('${Directory.systemTemp.path}/comic_online_resume_${DateTime.now().microsecondsSinceEpoch}.png')
      ..writeAsBytesSync(_pngBytes);

    await tester.pumpWidget(
      _page(target, _FakeCache(png), progressStore: progress),
    );
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, '海贼');
    await tester.tap(find.text('搜索'));
    await _settle(tester);
    await tester.tap(find.text('海贼王'));
    await _settle(tester);

    expect(find.text('继续看 第1186话'), findsOneWidget);
  });

  testWidgets('阅读器：默认竖向连续，点按钮换成左右翻页并记住', (tester) async {
    final source = _seed();
    final card = source.searchRules['bookList']!;
    final container = firstSelectorRule(source.bookInfoRules['tocUrl']!)!;
    final target = FakeComicTarget(
      counts: {card: 1, container: 1},
      perElement: {
        '$card|${source.searchRules['name']}': ['海贼王'],
        '$card|${source.searchRules['bookUrl']}': ['/comic/haizeiwang'],
        '$container|${source.tocRules['chapterName']}': ['第1186话'],
        '$container|${source.tocRules['chapterUrl']}': ['/c/1186'],
      },
      values: {
        source.bookInfoRules['name']!: ['航海王'],
        source.bookInfoRules['author']!: ['尾田荣一郎'],
      },
      jsSegment: '<img src="https://s1.bzcdn.net/a/1.jpg">',
    );
    final prefs = ComicReaderPrefs(
      cacheStore: CacheStore.inMemory('online_page_prefs_test'),
    );
    final png = File('${Directory.systemTemp.path}/comic_online_turn_${DateTime.now().microsecondsSinceEpoch}.png')
      ..writeAsBytesSync(_pngBytes);

    await tester.pumpWidget(
      _page(target, _FakeCache(png), readerPrefs: prefs),
    );
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, '海贼');
    await tester.tap(find.text('搜索'));
    await _settle(tester);
    await tester.tap(find.text('海贼王'));
    await _settle(tester);
    await tester.tap(find.text('第1186话'));
    await _settle(tester);

    // 默认竖向：没有分页控件
    expect(find.byType(PageView), findsNothing);
    expect(find.text('1 / 1 张'), findsOneWidget);

    // 点切换 → 变成左右翻页
    await tester.tap(find.byIcon(Icons.view_carousel_outlined));
    await _settle(tester);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('1 / 1 张'), findsOneWidget);

    // 偏好被记住（下次进来还是左右翻页）
    expect(await prefs.pageTurn(), isTrue);

    // 再点回来
    await tester.tap(find.byIcon(Icons.view_day_outlined));
    await _settle(tester);
    expect(find.byType(PageView), findsNothing);
    expect(await prefs.pageTurn(), isFalse);
  });

  testWidgets('取数方式要写在界面上：走快路就说快路', (tester) async {
    final source = _seed();
    final searchUrl = source.searchUrlFor('海贼')!;
    const cardClasses =
        'comics-card pure-u-1-2 pure-u-sm-1-2 pure-u-md-1-4 pure-u-lg-1-6';
    const html =
        '<html><body><div class="$cardClasses">'
        '<a href="/comic/haizeiwang"><amp-img src="https://c/a.jpg"></amp-img></a>'
        '<div class="comics-card__title text-truncate">海贼王</div></div></body></html>';
    final target = FakeComicTarget(responses: {searchUrl: html});
    final png = File('${Directory.systemTemp.path}/comic_online_path_${DateTime.now().microsecondsSinceEpoch}.png')
      ..writeAsBytesSync(_pngBytes);

    await tester.pumpWidget(_page(target, _FakeCache(png)));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, '海贼');
    await tester.tap(find.text('搜索'));
    await _settle(tester);

    expect(find.text('海贼王'), findsOneWidget);
    expect(find.text('取数方式：取 HTML 文本解析（快路）'), findsOneWidget);
  });
}

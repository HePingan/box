// 在线页面：搜索 → 详情/目录 → 阅读 三态切换的界面用例。
//
// 用假取数 + 假图片缓存：不联网、不起 WebView、不读系统目录。
// 三条底线各有一条用例：结果能点进去 / 失败说人话 / 取不到图时不假装成功。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_image_cache.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/domain/comic_online_progress.dart';
import 'package:box/features/comic/domain/comic_reader_prefs.dart';
import 'package:box/features/comic/domain/comic_source.dart';
import 'package:box/features/comic/domain/sources/seed_comic_source.dart';
import 'package:box/features/comic/presentation/comic_online_page.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_comic_target.dart';

/// 只关心设备令牌的内存版加密存储（其余方法按接口补空实现）。
///
/// 单测里没有平台通道，所以走 `debugSetOpsSecretStore` 这道接缝。
class _FakeOpsSecretStore implements OpsSecretStore {
  final Map<String, String> tokens = <String, String>{};

  @override
  Future<String?> readApiToken(String serverId) async => tokens[serverId];

  @override
  Future<void> writeApiToken(String serverId, String token) async =>
      tokens[serverId] = token;

  @override
  Future<void> clearApiToken(String serverId) async => tokens.remove(serverId);

  @override
  Future<String?> readPassword(String serverId) async => null;

  @override
  Future<void> writePassword(String serverId, String password) async {}

  @override
  Future<void> clearPassword(String serverId) async {}

  @override
  Future<String?> readLegacyPassword() async => null;

  @override
  Future<void> clearLegacyPassword() async {}
}

/// 1×1 的透明 PNG（够 Image.file 解码）。
const List<int> _pngBytes = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// 假图片缓存：直接给一个真 PNG 文件（不下载），并记下取过哪些图。
class _FakeCache extends ComicImageCache {
  _FakeCache(this.file);

  final File file;
  final List<String> fetched = <String>[];

  @override
  Future<File> fetch(String url, {bool lowPriority = false, File? dest}) async {
    fetched.add(url);
    return file;
  }

  @override
  Future<File?> cachedFile(String url) async => file;
}

ComicSource _seed() => ComicSource.tryParse(kSeedComicSourceJson)!;

/// 造一个上传好假数据的页面。
///
/// 默认注入「包子漫画」（老路的用例都基于它）。
/// [builtinDefault] = true 时不注入书源，用页面自己的默认源（内置第一份 = 野蛮漫画）。
Widget _page(
  FakeComicTarget target,
  _FakeCache cache, {
  ComicSource? source,
  bool builtinDefault = false,
  String? relayToken,
  ComicLibraryStore? libraryStore,
  ComicOnlineProgressStore? progressStore,
  ComicReaderPrefs? readerPrefs,
  String? initialBookUrl,
  Widget Function(String sourceName)? selfCheckPageBuilder,
}) {
  return MaterialApp(
    home: ComicOnlinePage(
      source: builtinDefault ? null : (source ?? _seed()),
      targetBuilder: () => target,
      imageCache: cache,
      relayToken: relayToken,
      selfCheckPageBuilder: selfCheckPageBuilder,
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

/// 带「上一层」的宿主：先有"书库"那一层，再 push 在线页 —— 这样才能验证
/// 「返回是一层层退，还是一跳跳到最上层」。[_page] 把在线页当第一个路由，
/// 本来就 pop 不动，测不了这个。
Widget _host(
  FakeComicTarget target,
  _FakeCache cache, {
  ComicSource? source,
  String? relayToken,
  String? initialBookUrl,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ComicOnlinePage(
                  source: source ?? _seed(),
                  targetBuilder: () => target,
                  imageCache: cache,
                  relayToken: relayToken,
                  waitTimeout: const Duration(milliseconds: 20),
                  listTimeout: const Duration(milliseconds: 20),
                  openTimeout: const Duration(milliseconds: 20),
                  initialBookUrl: initialBookUrl,
                  libraryStore: ComicLibraryStore(
                    cacheStore: CacheStore.inMemory('host_shelf'),
                  ),
                  readerPrefs: ComicReaderPrefs(
                    cacheStore: CacheStore.inMemory('host_prefs'),
                  ),
                  progressStore: ComicOnlineProgressStore(
                    cacheStore: CacheStore.inMemory('host_progress'),
                  ),
                ),
              ),
            ),
            child: const Text('书库'),
          ),
        ),
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

/// 把在途的取图轮询真跑完：服务里是 250ms 一轮、最长 12 秒。
///
/// 为什么要单独一个（别用 [_settle]）：帧循环的 1.6 秒不够，测试会以"还有定时器挂着"
/// 直接判失败 —— 那是**测试**欠的账，不是产品的问题。
Future<void> drainPolls(WidgetTester tester) async {
  // 40 秒假时钟（160 × 250ms）：一次切换会牵出"本话取图 + 顺手预取下一话"两轮轮询，
  // 每轮最长 12 秒，而且第二轮是**第一轮跑完之后**才开始的 —— 推得不够就会在收尾时
  // 被"还有定时器挂着"判失败。pump 只推假时钟，不真等，所以多推没有代价。
  for (var i = 0; i < 160; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// 野蛮漫画搜索页的真形状（照实测 HTML 写：`li.item.comic-item` → `p.title` / `a[href]` / `img[src]`）。
/// 直连那条路（快路 = 页内取这份 HTML）用它；规则改了这里会红。
const String _yemanSearchHtml = '''
<html><body>
<ul class="comic-sort col3" id="js_comicSortList">
  <li class="item comic-item">
    <a href="/book/7530/" title="海贼王~,海贼王~漫画">
      <div class="thumbnail"><img class="img" src="https://tuer.justpic01pt.com:666/picbed/CPMH/haizeiwang/a.jpg" alt="海贼王~"></div>
      <p class="title">海贼王~</p>
    </a>
  </li>
</ul>
</body></html>''';

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

  testWidgets('搜索失败时给「自检这个源」，带的是**当前这份源**（用户只有手机，这是他拿结论的路）',
      (tester) async {
    final source = _seed(); // 包子漫画（优）—— 内置清单第二份，"预选"和"默认第一份"能区分开
    final card = source.searchRules['bookList']!;
    final target = FakeComicTarget(
      counts: {card: 1},
      perElement: {
        '$card|${source.searchRules['name']}': ['甲'],
        '$card|${source.searchRules['bookUrl']}': [''],
      },
    );
    String? passedName;

    await tester.pumpWidget(
      _page(
        target,
        _FakeCache(png),
        selfCheckPageBuilder: (name) {
          passedName = name;
          return Scaffold(body: Text('自检页：$name'));
        },
      ),
    );
    await tester.enterText(find.byType(TextField), 'x');
    await tester.tap(find.text('搜索'));
    await _settle(tester);

    expect(find.text('重试'), findsOneWidget, reason: '原来的重试不能少');
    await tester.tap(find.text('自检这个源'));
    await _settle(tester);

    expect(passedName, '包子漫画（优）', reason: '从哪份源进来就预选哪份源，别让人再挑一次');
    expect(find.text('自检页：包子漫画（优）'), findsOneWidget);
  });

  testWidgets('书源菜单里也挂着「自检这份源」（源出问题时不用先跑回漫画库）', (tester) async {
    final target = FakeComicTarget(
      counts: {_seed().searchRules['bookList']!: 1},
      perElement: {
        '${_seed().searchRules['bookList']}|${_seed().searchRules['name']}': ['甲'],
        '${_seed().searchRules['bookList']}|${_seed().searchRules['bookUrl']}': ['/comic/a'],
      },
    );
    String? passedName;

    await tester.pumpWidget(
      _page(
        target,
        _FakeCache(png),
        selfCheckPageBuilder: (name) {
          passedName = name;
          return Scaffold(body: Text('自检页：$name'));
        },
      ),
    );
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.source_outlined));
    await _settle(tester);
    expect(find.text('自检「包子漫画（优）」'), findsOneWidget);

    await tester.tap(find.text('自检「包子漫画（优）」'));
    await _settle(tester);

    expect(passedName, '包子漫画（优）');
  });

  testWidgets('正常搜索时没有「自检这个源」（控制组：它不是常驻按钮）', (tester) async {
    final source = _seed();
    final card = source.searchRules['bookList']!;
    final target = FakeComicTarget(
      counts: {card: 1},
      perElement: {
        '$card|${source.searchRules['name']}': ['海贼王'],
        '$card|${source.searchRules['bookUrl']}': ['/comic/haizeiwang'],
      },
    );

    await tester.pumpWidget(_page(target, _FakeCache(png)));
    await tester.enterText(find.byType(TextField), 'x');
    await tester.tap(find.text('搜索'));
    await _settle(tester);

    expect(find.text('海贼王'), findsOneWidget, reason: '先确认这次是成功的');
    expect(find.text('自检这个源'), findsNothing);
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

  testWidgets('切换书源：从「野蛮漫画」切到「包子漫画」后按老路走', (tester) async {
    final baozimh = _seed();
    final card = baozimh.searchRules['bookList']!;
    final target = FakeComicTarget(
      counts: {card: 1},
      perElement: {
        '$card|${baozimh.searchRules['name']}': ['海贼王'],
        '$card|${baozimh.searchRules['bookUrl']}': ['/comic/haizeiwang'],
      },
    );
    final png = File(
      '${Directory.systemTemp.path}/comic_online_src_'
      '${DateTime.now().microsecondsSinceEpoch}.png',
    )..writeAsBytesSync(_pngBytes);

    // 不注入书源（用内置第一份 = 野蛮漫画）；显式给"没有令牌"，免得测试里去读设置。
    await tester.pumpWidget(
      _page(target, _FakeCache(png), builtinDefault: true, relayToken: ''),
    );
    await _settle(tester);

    // 默认源是野蛮漫画：没配令牌就是**直连**，不再要求先去填令牌（也不是错误页）
    expect(find.textContaining('设备令牌'), findsNothing);

    // 两个内置源都列在菜单里，包子那份带着"连不上"的备注
    await tester.tap(find.byIcon(Icons.source_outlined));
    await _settle(tester);
    expect(find.text('野蛮漫画'), findsOneWidget);
    expect(find.text('包子漫画（优）'), findsOneWidget);
    expect(find.textContaining('连接被重置'), findsOneWidget);

    await tester.tap(find.text('包子漫画（优）'));
    await _settle(tester);

    // 换源之后同样没有"设备令牌"这类提示
    expect(find.textContaining('设备令牌'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '海贼');
    await tester.tap(find.text('搜索'));
    await _settle(tester);

    expect(find.text('海贼王'), findsOneWidget);
    // 老路：真的去打开了站点的搜索页（快路在假目标里取不到响应，必然退到这条）
    expect(target.opened, anyElement(contains('/search?q=')));
  });

  testWidgets('默认「野蛮漫画」但没有设备令牌 → 直连站点就能搜（不提示去填、不是错误页）', (tester) async {
    final yeman = ComicSource.tryParse(kSeedComicSourceYemanJson)!;
    final searchUrl = yeman.searchUrlFor('海贼')!;
    // 快路（直连：页内取这份 HTML）—— 全程不经任何服务器
    final target = FakeComicTarget(responses: {searchUrl: _yemanSearchHtml});
    final png = File(
      '${Directory.systemTemp.path}/comic_online_notoken_'
      '${DateTime.now().microsecondsSinceEpoch}.png',
    )..writeAsBytesSync(_pngBytes);

    await tester.pumpWidget(
      _page(target, _FakeCache(png), builtinDefault: true, relayToken: ''),
    );
    await _settle(tester);

    // 没有令牌不再拦人：不提「设备令牌」，也没有错误页
    expect(find.textContaining('设备令牌'), findsNothing);
    expect(find.text('重试'), findsNothing);
    expect(find.textContaining('输入关键字'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '海贼');
    await tester.tap(find.text('搜索'));
    await _settle(tester);

    // 直连真的发了请求、结果出来了 —— 不需要任何令牌 / 中转
    expect(target.fetched, contains(searchUrl));
    expect(find.textContaining('海贼王'), findsWidgets);
  });

  // 中转令牌**取哪一台**：服务在 175，`box.hpa888.top` 只是边缘机反代。
  // 取错那台（hpa888）的令牌 → 每个请求都 401（公网入口实测过），所以要有护栏。
  group('中转令牌取哪一台', () {
    late _FakeOpsSecretStore store;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = _FakeOpsSecretStore();
      debugSetOpsSecretStore(store);
    });

    tearDown(() => debugSetOpsSecretStore());

    test('两台都填了 → 取中转所在那台（175），不是入口域名那台', () async {
      store.tokens['hpa888'] = 'tok-hpa888';
      store.tokens['tencent175'] = 'tok-175';

      expect(await loadComicRelayToken(), 'tok-175');
    });

    test('只填了 hpa888 那把 → 空串：宁可走直连，也不把另一台的令牌发给 175', () async {
      store.tokens['hpa888'] = 'tok-hpa888';

      expect(await loadComicRelayToken(), '');
    });

    test('没填 → 空串（不抛：走直连就是了，不是错误）', () async {
      expect(await loadComicRelayToken(), '');
    });
  });

  // 返回必须**一层层退**（2026-09-29 用户报：「返回直接回到最上层页面」）。
  // 两个坑：① 从书库直接进详情时后面本来没有"搜索"这一层，照写死的阶梯退会退到一个
  // 空搜索页；② 系统返回（手势/返回键）没接住，在阅读里一按就退出整个页面。
  group('返回：一层层退', () {
    FakeComicTarget fullTarget() {
      final source = _seed();
      final card = source.searchRules['bookList']!;
      final container = firstSelectorRule(source.bookInfoRules['tocUrl']!)!;
      return FakeComicTarget(
        counts: {card: 1, container: 1},
        perElement: {
          '$card|${source.searchRules['name']}': ['海贼王'],
          '$card|${source.searchRules['bookUrl']}': ['/comic/haizeiwang'],
          '$container|${source.tocRules['chapterName']}': ['第1186话'],
          '$container|${source.tocRules['chapterUrl']}': [
            '/user/page_direct?slot=1186',
          ],
        },
        values: {
          source.bookInfoRules['name']!: ['航海王'],
          source.bookInfoRules['author']!: ['尾田荣一郎'],
        },
        jsSegment: '<img src="https://s1.bzcdn.net/a/1.jpg">',
      );
    }

    Future<void> openHost(WidgetTester tester, Widget app) async {
      await tester.pumpWidget(app);
      await tester.tap(find.text('书库'));
      await _settle(tester);
    }

    Future<void> searchToReader(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField), '海贼');
      await tester.tap(find.text('搜索'));
      await _settle(tester);
      await tester.tap(find.text('海贼王'));
      await _settle(tester);
      await tester.tap(find.text('第1186话'));
      await _settle(tester);
      expect(find.text('1 / 1 张'), findsOneWidget, reason: '先进到阅读里');
    }

    testWidgets('阅读 → 详情 → 列表 → 退出：一层层退，不跳到底', (tester) async {
      await openHost(tester, _host(fullTarget(), _FakeCache(png)));
      await searchToReader(tester);

      // ① 阅读里按返回 → 回详情（不是直接退出本页）
      await tester.tap(find.byIcon(Icons.arrow_back));
      await _settle(tester);
      expect(find.text('1 / 1 张'), findsNothing);
      expect(find.text('共 1 话'), findsOneWidget);
      expect(find.text('书库'), findsNothing, reason: '不该跳回最上层');

      // ② 详情里按返回 → 回列表
      await tester.tap(find.byIcon(Icons.arrow_back));
      await _settle(tester);
      expect(find.text('共 1 话'), findsNothing);
      expect(find.text('海贼王'), findsOneWidget);
      expect(find.text('书库'), findsNothing);

      // ③ 列表里按返回 → 这才真的退出本页，回到书库那一层
      await tester.tap(find.byIcon(Icons.arrow_back));
      await _settle(tester);
      expect(find.text('书库'), findsOneWidget);
      expect(find.text('海贼王'), findsNothing);
    });

    testWidgets('从书库直接进一本：返回就退出本页，不经过空搜索页', (tester) async {
      await openHost(
        tester,
        _host(
          fullTarget(),
          _FakeCache(png),
          initialBookUrl: 'https://cn.baozimhcn.com/comic/haizeiwang',
        ),
      );
      expect(find.text('共 1 话'), findsOneWidget, reason: '从书库进来直接是详情');

      await tester.tap(find.byIcon(Icons.arrow_back));
      await _settle(tester);

      expect(find.text('书库'), findsOneWidget);
      expect(find.textContaining('输入关键字'), findsNothing, reason: '别停在空搜索页');
    });

    testWidgets('系统返回键与箭头同一个口径：阅读里退到详情，不退到最上层', (tester) async {
      await openHost(tester, _host(fullTarget(), _FakeCache(png)));
      await searchToReader(tester);

      // Android 返回键 / 手势返回走的就是这条（flutter/navigation → popRoute）
      await tester.binding.handlePopRoute();
      await _settle(tester);

      expect(find.text('1 / 1 张'), findsNothing);
      expect(find.text('共 1 话'), findsOneWidget);
      expect(find.text('书库'), findsNothing, reason: '系统返回也得一层层退');
    });
  });

  group('上一话 / 下一话（目录正序：index 大的更晚）', () {
    /// 三话的书：槽位各不相同，好判断"到底碰了哪一话"。
    FakeComicTarget threeChapters() {
      final source = _seed();
      final card = source.searchRules['bookList']!;
      final container = firstSelectorRule(source.bookInfoRules['tocUrl']!)!;
      return FakeComicTarget(
        counts: {card: 1, container: 3},
        perElement: {
          '$card|${source.searchRules['name']}': ['海贼王'],
          '$card|${source.searchRules['bookUrl']}': ['/comic/haizeiwang'],
          '$container|${source.tocRules['chapterName']}': ['第1话', '第2话', '第3话'],
          '$container|${source.tocRules['chapterUrl']}': [
            '/user/page_direct?slot=11',
            '/user/page_direct?slot=22',
            '/user/page_direct?slot=33',
          ],
        },
        values: {
          source.bookInfoRules['name']!: ['航海王'],
          source.bookInfoRules['author']!: ['尾田荣一郎'],
        },
        jsSegment: '<img src="https://s1.bzcdn.net/a/1.jpg">',
      );
    }

    Future<void> openHost(WidgetTester tester, Widget app) async {
      await tester.pumpWidget(app);
      await tester.tap(find.text('书库'));
      await _settle(tester);
    }

    /// 预取是异步的（`unawaited`）：跑全量时和其它用例文件抢 CPU，固定 pump 次数不够稳，
    /// 要等到"某个请求真的发生了"再断言（单独跑这个文件时不稳的那次就是这么露出来的）。
    Future<void> waitForRequest(
      WidgetTester tester,
      FakeComicTarget target,
      String part,
    ) async {
      for (var i = 0; i < 300; i++) {
        if (target.requests.any((r) => r.contains(part))) return;
        await tester.pump(const Duration(milliseconds: 10));
        await Future<void>.delayed(Duration.zero);
      }
    }

    Future<void> openChapterAt(WidgetTester tester, String title) async {
      await tester.enterText(find.byType(TextField), '海贼');
      await tester.tap(find.text('搜索'));
      await _settle(tester);
      await tester.tap(find.text('海贼王'));
      await _settle(tester);
      await tester.tap(find.text(title));
      await _settle(tester);
    }

    testWidgets('「下一话」开目录里更晚的那一话（这曾经写反成上一话）', (tester) async {
      final target = threeChapters();
      await openHost(tester, _host(target, _FakeCache(png)));
      await openChapterAt(tester, '第2话');

      // 清掉进第2话时的请求（含预取），只看这一下点出来的效果
      target.opened.clear();
      target.fetched.clear();
      await tester.tap(find.text('下一话'));
      await waitForRequest(tester, target, 'slot=33');
      // 等到之后还要把在途的收尾（服务里那 250ms 一轮的取图轮询）走完：测试结束得比它早，
      // 框架会以"还有定时器挂着"直接判失败。
      await drainPolls(tester);

      expect(
        target.requests,
        contains('https://cn.baozimhcn.com/user/page_direct?slot=33'),
        reason: '「下一话」= 目录里 index 更大的那一话',
      );
    });

    testWidgets('「上一话」开目录里更早的那一话', (tester) async {
      final target = threeChapters();
      await openHost(tester, _host(target, _FakeCache(png)));
      await openChapterAt(tester, '第2话');

      target.opened.clear();
      target.fetched.clear();
      await tester.tap(find.text('上一话'));
      await waitForRequest(tester, target, 'slot=11');
      // 等到之后还要把在途的收尾（服务里那 250ms 一轮的取图轮询）走完：测试结束得比它早，
      // 框架会以"还有定时器挂着"直接判失败。
      await drainPolls(tester);

      expect(
        target.requests,
        contains('https://cn.baozimhcn.com/user/page_direct?slot=11'),
        reason: '「上一话」= 目录里 index 更小的那一话',
      );
    });

    testWidgets('第1话没有上一话：按钮置灰，不乱跳', (tester) async {
      final target = threeChapters();
      await openHost(tester, _host(target, _FakeCache(png)));
      await openChapterAt(tester, '第1话');

      final back = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '上一话'),
      );
      expect(back.onPressed, isNull, reason: '第1话的上一话按钮该是灰的');

      target.opened.clear();
      target.fetched.clear();
      await tester.tap(find.text('下一话'));
      await waitForRequest(tester, target, 'slot=22');
      // 等到之后还要把在途的收尾（服务里那 250ms 一轮的取图轮询）走完：测试结束得比它早，
      // 框架会以"还有定时器挂着"直接判失败。1.6 秒的 _settle 不够（轮询最长 12 秒），
      // 这里按轮询的节奏把假时钟推够。
      await drainPolls(tester);
      expect(
        target.requests,
        contains('https://cn.baozimhcn.com/user/page_direct?slot=22'),
        reason: '第1话的下一话是第2话',
      );
    });

    testWidgets('最后一话没有下一话：按钮置灰，不乱跳', (tester) async {
      final target = threeChapters();
      await openHost(tester, _host(target, _FakeCache(png)));
      await openChapterAt(tester, '第3话');

      final forward = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '下一话'),
      );
      expect(forward.onPressed, isNull, reason: '最后一话的下一话按钮该是灰的');
    });

    testWidgets('读到本话（只剩 2 张以内）：顺手把下一话开头几张取回来', (tester) async {
      final target = threeChapters();
      final cache = _FakeCache(png);
      await openHost(tester, _host(target, cache));
      await openChapterAt(tester, '第2话');
      await waitForRequest(tester, target, 'slot=33');
      // 等到之后还要把在途的收尾（服务里那 250ms 一轮的取图轮询）走完：测试结束得比它早，
      // 框架会以"还有定时器挂着"直接判失败。
      await drainPolls(tester);

      final req = target.requests.join(' ');
      expect(req, contains('slot=33'), reason: '第2话里就该问第3话');
      expect(req, isNot(contains('slot=11')), reason: '预取只认下一话，不往回取');
      expect(find.text('1 / 1 张'), findsOneWidget, reason: '预取不该换掉正在看的这一话');
    });

    testWidgets('还早得很（没读到末尾）就不预取：别白费流量', (tester) async {
      final source = _seed();
      final card = source.searchRules['bookList']!;
      final container = firstSelectorRule(source.bookInfoRules['tocUrl']!)!;
      final target = FakeComicTarget(
        counts: {card: 1, container: 2},
        perElement: {
          '$card|${source.searchRules['name']}': ['海贼王'],
          '$card|${source.searchRules['bookUrl']}': ['/comic/haizeiwang'],
          '$container|${source.tocRules['chapterName']}': ['第1话', '第2话'],
          '$container|${source.tocRules['chapterUrl']}': [
            '/user/page_direct?slot=11',
            '/user/page_direct?slot=22',
          ],
        },
        values: {
          source.bookInfoRules['name']!: ['航海王'],
          source.bookInfoRules['author']!: ['尾田荣一郎'],
        },
        // 一话 5 张：刚进来还在第 1 张，离末尾还差 4 张
        jsSegment: [
          for (var i = 1; i <= 5; i++) '<img src="https://s1.bzcdn.net/a/$i.jpg">',
        ].join(),
      );

      await openHost(tester, _host(target, _FakeCache(png)));
      await openChapterAt(tester, '第1话');

      expect(
        target.requests.join(' '),
        isNot(contains('slot=22')),
        reason: '才第 1 张就去取下一话 = 白费流量',
      );
    });

    testWidgets('底部控制栏：能收起来（点画面），过几秒也会自己收起', (tester) async {
      final target = threeChapters();
      await openHost(tester, _host(target, _FakeCache(png)));
      await openChapterAt(tester, '第1话');

      // 控制栏是 AnimatedOpacity 包着的（收起时**留在树上**、只是透明），
      // 所以"有没有收起来"看透明度，别看 findsWidgets。
      double chromeOpacity() => tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.text('1 / 1 张'),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;

      expect(chromeOpacity(), 1, reason: '刚进来要看得见（不然找不到按钮）');

      // 点画面（画面中间，不是底部那条）→ 收起来，不挡着看
      await tester.tapAt(const Offset(400, 250));
      await _settle(tester);
      expect(chromeOpacity(), 0, reason: '点一下画面该收起来');

      await tester.tapAt(const Offset(400, 250));
      await _settle(tester);
      expect(chromeOpacity(), 1, reason: '再点一下要能叫回来');

      // 什么都不做也会自己收起（不用用户去点）
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 200));
      expect(chromeOpacity(), 0, reason: '几秒后自己收起');
    });
    testWidgets('页漫：点左右两侧翻一张，点中间收/放控制栏，到头有说明', (tester) async {
      final source = _seed();
      final card = source.searchRules['bookList']!;
      final container = firstSelectorRule(source.bookInfoRules['tocUrl']!)!;
      final target = FakeComicTarget(
        counts: {card: 1, container: 1},
        perElement: {
          '$card|${source.searchRules['name']}': ['海贼王'],
          '$card|${source.searchRules['bookUrl']}': ['/comic/haizeiwang'],
          '$container|${source.tocRules['chapterName']}': ['第1话'],
          '$container|${source.tocRules['chapterUrl']}': ['/user/page_direct?slot=11'],
        },
        values: {
          source.bookInfoRules['name']!: ['航海王'],
          source.bookInfoRules['author']!: ['尾田荣一郎'],
        },
        // 一话 3 张：够验证"左右各翻一张"和"到头"两种情况
        jsSegment: [
          for (var i = 1; i <= 3; i++)
            '<img src="https://s1.bzcdn.net/a/$i.jpg">',
        ].join(),
      );

      await openHost(tester, _host(target, _FakeCache(png)));
      await openChapterAt(tester, '第1话');

      // 切成左右翻页（页漫）
      await tester.tap(find.byIcon(Icons.view_carousel_outlined));
      await _settle(tester);
      expect(find.text('1 / 3 张'), findsOneWidget);

      // 右侧 1/3 → 下一张（800 宽的面板，700 落在右区）
      await tester.tapAt(const Offset(700, 250));
      await tester.pump(const Duration(milliseconds: 100));
      await _settle(tester);
      expect(find.text('2 / 3 张'), findsOneWidget, reason: '点右边该翻到下一张');

      // 左侧 1/3 → 回上一张
      await tester.tapAt(const Offset(100, 250));
      await _settle(tester);
      expect(find.text('1 / 3 张'), findsOneWidget, reason: '点左边该回到上一张');

      // 已经是第一张再往左：给一句说明，不能"点了没反应"
      await tester.tapAt(const Offset(100, 250));
      await _settle(tester);
      expect(find.text('已经是第一张了'), findsOneWidget);

      // 点中间（400 = 正中间）→ 收/放控制栏，不翻页
      await tester.pump(const Duration(seconds: 5)); // 先让它自动收起
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tapAt(const Offset(400, 250));
      await _settle(tester);
      expect(find.text('1 / 3 张'), findsOneWidget, reason: '中间不翻页');
      final opacity = tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.text('1 / 3 张'),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;
      expect(opacity, 1, reason: '点中间把控制栏叫回来');
    });

    testWidgets('阅读器里能直接挑话（不用退回详情页）', (tester) async {
      final target = threeChapters();
      await openHost(tester, _host(target, _FakeCache(png)));
      await openChapterAt(tester, '第1话');
      expect(target.requests.join(' '), isNot(contains('slot=33')));

      // 控制栏 4 秒后自己收起：先把它叫出来再点（不然点在被忽略的透明处）
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tapAt(const Offset(400, 250));
      await _settle(tester);

      // 目录按钮 → 弹出话列表 → 点第 3 话
      await tester.tap(find.byTooltip('目录（直接挑话）'));
      await _settle(tester);
      expect(find.text('第2话'), findsWidgets, reason: '目录里该有话列表');

      await tester.tap(find.text('第3话').last);
      await _settle(tester);
      expect(
        target.requests.join(' '),
        contains('slot=33'),
        reason: '挑话之后要真的去取那一话',
      );
    });

    testWidgets('长按图片：开全屏放大查看，关掉回到原来那一张', (tester) async {
      final target = threeChapters();
      await openHost(tester, _host(target, _FakeCache(png)));
      await openChapterAt(tester, '第1话');

      // 长按图片 → 放大（用长按而不是双击：双击会把单击拖慢，实测过）
      await tester.longPressAt(tester.getCenter(find.byType(Image).first));
      await _settle(tester);

      expect(find.byType(InteractiveViewer), findsOneWidget, reason: '长按要放大来看');
      expect(find.textContaining('捏合放大'), findsOneWidget);

      await tester.tap(find.byTooltip('关闭（也可以双击图片）'));
      await _settle(tester);
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.text('1 / 1 张'), findsOneWidget, reason: '关掉回到原来那一张');
    });

    testWidgets('进阅读器隐藏状态栏（沉浸），退出来恢复', (tester) async {
      final modes = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
            modes.add('${call.arguments}');
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      final target = threeChapters();
      await openHost(tester, _host(target, _FakeCache(png)));
      await openChapterAt(tester, '第1话');
      expect(
        modes.any((m) => m.contains('immersiveSticky')),
        isTrue,
        reason: '进阅读器要隐藏状态栏/导航条',
      );

      // 返回详情：状态栏还回去
      await tester.tap(find.byIcon(Icons.arrow_back));
      await _settle(tester);
      expect(
        modes.any((m) => m.contains('edgeToEdge')),
        isTrue,
        reason: '离开阅读器要把状态栏还回来',
      );
    });
  });
}
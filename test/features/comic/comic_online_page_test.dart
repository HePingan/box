// 在线页面：搜索 → 详情/目录 → 阅读 三态切换的界面用例。
//
// 用假取数 + 假图片缓存：不联网、不起 WebView、不读系统目录。
// 三条底线各有一条用例：结果能点进去 / 失败说人话 / 取不到图时不假装成功。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/comic/domain/comic_image_cache.dart';
import 'package:box/features/comic/domain/comic_online_progress.dart';
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
Widget _page(FakeComicTarget target, _FakeCache cache) {
  return MaterialApp(
    home: ComicOnlinePage(
      source: _seed(),
      targetBuilder: () => target,
      imageCache: cache,
      waitTimeout: const Duration(milliseconds: 20),
      listTimeout: const Duration(milliseconds: 20),
      openTimeout: const Duration(milliseconds: 20),
      progressStore: ComicOnlineProgressStore(
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
      MaterialApp(
        home: ComicOnlinePage(
          source: _seed(),
          targetBuilder: () => target,
          imageCache: _FakeCache(png),
          waitTimeout: const Duration(milliseconds: 20),
          listTimeout: const Duration(milliseconds: 20),
          openTimeout: const Duration(milliseconds: 20),
          progressStore: ComicOnlineProgressStore(
            cacheStore: CacheStore.inMemory('online_page_test2'),
          ),
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
}

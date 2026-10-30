import 'dart:convert';

import 'package:box/features/extensions/plugins/wallpaper/data/wallpaper_api.dart';
import 'package:box/features/extensions/plugins/wallpaper/presentation/wallpaper_gallery_page.dart';
import 'package:box/features/extensions/plugins/wallpaper/domain/wallpaper_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 清单拉取 + 图库页面（数据源与保存动作都注入，不联网、不碰相册）。
class _FakeSource implements WallpaperSource {
  _FakeSource(this.manifest, {this.failTimes = 0});

  final WallpaperManifest manifest;
  int failTimes;
  int calls = 0;

  @override
  Future<WallpaperManifest> load() async {
    calls++;
    if (failTimes > 0) {
      failTimes--;
      throw const WallpaperManifestException('网络不可用');
    }
    return manifest;
  }
}

WallpaperManifest _manifest() => const WallpaperManifest(
      baseUrl: 'https://a.com/w/',
      source: '测试源 · 仅个人使用',
      items: [
        WallpaperItem(
          id: 'wp-01',
          title: '金发与柔光',
          file: 'wp-01.jpg',
          thumb: 'wp-01-t.jpg',
          width: 1896,
          height: 2560,
          bytes: 682000,
          tags: ['金发', '柔和'],
        ),
        WallpaperItem(
          id: 'wp-02',
          title: '蓝调骑士',
          file: 'wp-02.jpg',
          thumb: 'wp-02-t.jpg',
          width: 1294,
          height: 2300,
          bytes: 476000,
          tags: ['奇幻'],
        ),
        WallpaperItem(
          id: 'wp-03',
          title: '霓虹街的银发',
          file: 'wp-03.jpg',
          thumb: 'wp-03-t.jpg',
          width: 1414,
          height: 2000,
          tags: ['霓虹', '金发'],
        ),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  required WallpaperSource source,
  WallpaperSaver? saver,
}) async {
  // 默认测试视口 800×600 装不下 2 列 9:19.5 的壁纸卡片：卡片底部的标题会落到
  // 视口外，`tester.tap(find.text(...))` 会「点了但没命中」（还只给一条 warning）。
  // 换成真机逻辑尺寸（360×800）才和真实观感一致。
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  debugSetWallpaperRuntime(source: source, saver: saver);
  await tester.pumpWidget(const MaterialApp(home: WallpaperGalleryPage()));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => debugSetWallpaperRuntime());

  group('WallpaperApi', () {
    test('200 + UTF-8 中文清单 → 解析出条目', () async {
      final body = jsonEncode({
        'baseUrl': 'https://a.com/w/',
        'source': '樱道 · 仅个人使用',
        'items': [
          {'id': 'wp-01', 'title': '金发与柔光', 'file': 'wp-01.jpg', 'width': 1896, 'height': 2560},
        ],
      });
      final api = WallpaperApi(
        manifestUrl: Uri.parse('https://a.com/w/manifest.json'),
        httpClient: MockClient((req) async => http.Response.bytes(
              utf8.encode(body),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      );
      final m = await api.load();
      expect(m.items.single.title, '金发与柔光');
      expect(m.source, '樱道 · 仅个人使用');
    });

    test('非 200 → 抛异常并写出状态码', () async {
      final api = WallpaperApi(
        manifestUrl: Uri.parse('https://a.com/w/manifest.json'),
        httpClient: MockClient((req) async => http.Response('nope', 503)),
      );
      await expectLater(
        api.load(),
        throwsA(
          isA<WallpaperManifestException>().having(
            (e) => e.message,
            'message',
            contains('503'),
          ),
        ),
      );
    });

    test('网络异常 → 抛可读异常（不是 SocketException 冒泡）', () async {
      final api = WallpaperApi(
        manifestUrl: Uri.parse('https://a.com/w/manifest.json'),
        httpClient: MockClient((req) async => throw Exception('dns fail')),
      );
      await expectLater(
        api.load(),
        throwsA(isA<WallpaperManifestException>()),
      );
    });
  });

  group('图库页面', () {
    testWidgets('渲染清单里的壁纸与数量', (tester) async {
      await _pump(tester, source: _FakeSource(_manifest()));

      expect(find.text('动漫壁纸'), findsOneWidget);
      expect(find.text('3 张'), findsOneWidget);
      expect(find.text('金发与柔光'), findsOneWidget);
      expect(find.text('蓝调骑士'), findsOneWidget);
    });

    testWidgets('标签筛选：点「金发」只剩两张', (tester) async {
      await _pump(tester, source: _FakeSource(_manifest()));

      await tester.tap(find.widgetWithText(FilterChip, '金发'));
      await tester.pumpAndSettle();

      expect(find.text('2 张'), findsOneWidget);
      expect(find.text('蓝调骑士'), findsNothing);
      expect(find.text('霓虹街的银发'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, '全部'));
      await tester.pumpAndSettle();
      expect(find.text('3 张'), findsOneWidget);
    });

    testWidgets('点一张进预览，显示分辨率/来源，保存动作被调用', (tester) async {
      final saved = <WallpaperItem>[];
      await _pump(
        tester,
        source: _FakeSource(_manifest()),
        saver: (item) async => saved.add(item),
      );

      await tester.tap(find.text('金发与柔光'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1896 × 2560'), findsOneWidget);
      expect(find.textContaining('测试源'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '保存到相册'));
      await tester.pumpAndSettle();

      expect(saved.single.id, 'wp-01');
      expect(find.textContaining('已保存到相册'), findsOneWidget);
    });

    testWidgets('保存失败要如实说出原因', (tester) async {
      await _pump(
        tester,
        source: _FakeSource(_manifest()),
        saver: (item) async => throw const WallpaperManifestException('下载失败：HTTP 404'),
      );

      await tester.tap(find.text('蓝调骑士'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存到相册'));
      await tester.pumpAndSettle();

      expect(find.textContaining('保存失败'), findsOneWidget);
      expect(find.textContaining('404'), findsOneWidget);
    });

    testWidgets('拉取失败显示原因与重试，重试成功后正常出图', (tester) async {
      final source = _FakeSource(_manifest(), failTimes: 1);
      await _pump(tester, source: source);

      expect(find.textContaining('网络不可用'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '重试'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.text('3 张'), findsOneWidget);
      expect(source.calls, 2);
    });

    testWidgets('空清单给出明确空态而不是一片空白', (tester) async {
      await _pump(
        tester,
        source: _FakeSource(
          const WallpaperManifest(baseUrl: 'https://a.com/w/', items: []),
        ),
      );
      expect(find.text('清单里还没有壁纸'), findsOneWidget);
    });
  });
}

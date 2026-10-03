import 'dart:io';

import 'package:box/video/controller/video_catalog_repository.dart';
import 'package:box/video/models/video_category.dart';
import 'package:box/video/pages/home/home_source_sheet.dart';
import 'package:box/video_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归 ① 的另一半：选源面板必须与聚合搜索读**同一套**可见性真相。
///
/// 缺陷原形（home_source_sheet.dart）：
///   - 面板的「已自动隐藏」标签读的是模型字段 `source.hiddenReason`，
///     而 ① 的自动隐藏写在 `VideoModule` 的可见性层里 —— 两边不通，
///     于是被自动隐藏的源在面板上看着跟正常源一样、还能切过去；
///   - 面板没有任何恢复入口（唯一的写开关在 admin 插件的 tab 里）。
class _StubCatalogRepository extends VideoCatalogRepository {
  const _StubCatalogRepository(this.sources);

  final List<VideoSource> sources;

  @override
  Future<List<VideoSource>> loadSources(String catalogUrl) async => sources;

  @override
  Future<List<VideoCategory>> loadCategories(VideoSource source) async =>
      const <VideoCategory>[];

  @override
  Future<List<VodItem>> loadVideos(
    VideoSource source, {
    required int? typeId,
    required int page,
    String? typeQuery,
  }) async => const <VodItem>[];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('box_source_sheet_hive_');
    Hive.init(hiveDir.path);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VideoModule.resetForTest();
    VideoController.resetPrefsCacheForTesting();
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDir.existsSync()) {
      await hiveDir.delete(recursive: true);
    }
  });

  Future<VideoController> buildController() async {
    final sources = List.generate(
      3,
      (i) => VideoSource(
        id: 'src$i',
        name: '源$i',
        url: 'https://s$i.example.com/api.php/provide/vod/',
        detailUrl: '',
      ),
    );
    final controller = VideoController(
      repository: _StubCatalogRepository(sources),
    );
    await controller.initSources('https://catalog.example.com/list.json');
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> openSheet(
    WidgetTester tester,
    VideoController controller,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<VideoController>.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHomeSourcePickerSheet(context, controller),
                child: const Text('打开片源'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开片源'));
    await tester.pumpAndSettle();
  }

  testWidgets('被自动隐藏的源：面板显示「已自动隐藏 · 原因」，而不是装成正常源', (tester) async {
    final controller = await buildController();
    // 故意不用当前源（默认是 src0），否则「切没切过去」这类断言会假阳性。
    final broken = controller.sources[1];
    await VideoModule.setSourceAutoHidden(
      broken,
      true,
      reason: '接口层不可用：接口禁止关键词搜索',
      failCount: 3,
    );

    await openSheet(tester, controller);

    expect(
      find.textContaining('已自动隐藏'),
      findsWidgets,
      reason: '面板必须读到 ① 写的那套可见性，否则用户看不到源为什么没了',
    );
    expect(find.textContaining('接口禁止关键词搜索'), findsOneWidget);
    expect(find.textContaining('1 个已自动隐藏'), findsOneWidget);
    expect(find.text('恢复'), findsOneWidget);
    // 其余源照旧给「检测」。
    expect(find.text('检测'), findsWidgets);
  });

  testWidgets('点「恢复」后源回到可用：隐藏清掉、失败计数归零', (tester) async {
    final controller = await buildController();
    final broken = controller.sources[1];
    await VideoModule.setSourceAutoHidden(
      broken,
      true,
      reason: '接口层不可用：接口禁止关键词搜索',
      failCount: 3,
    );

    await openSheet(tester, controller);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    final record = VideoModule.getVisibilityRecord(broken);
    expect(record.isHidden, isFalse, reason: '恢复必须把自动隐藏清掉');
    expect(record.failCount, 0, reason: '失败计数不归零的话，面板仍按「连续失败 3 次」判它不可用');
    expect(find.text('恢复'), findsNothing);
    expect(find.text('检测'), findsWidgets);
  });

  testWidgets('手动隐藏的源同样能恢复', (tester) async {
    final controller = await buildController();
    final hidden = controller.sources.last;
    await VideoModule.setSourceManualHidden(hidden, true);

    await openSheet(tester, controller);
    expect(find.textContaining('已手动隐藏'), findsOneWidget);

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(VideoModule.getVisibilityRecord(hidden).isHidden, isFalse);
  });

  testWidgets('已自动隐藏的源不能直接切过去，点击提示要说清原因', (tester) async {
    final controller = await buildController();
    final broken = controller.sources[1];
    await VideoModule.setSourceAutoHidden(
      broken,
      true,
      reason: '接口层不可用：接口禁止关键词搜索',
      failCount: 3,
    );

    await openSheet(tester, controller);
    await tester.tap(
      find.ancestor(of: find.text('源1'), matching: find.byType(InkWell)),
    );
    await tester.pump();

    expect(
      controller.currentSource?.id,
      isNot(broken.id),
      reason: '切到一个搜索根本不会用的源，只会让用户看到空白',
    );
    expect(find.text('片源管理'), findsOneWidget, reason: '面板不该被关掉');
    expect(find.textContaining('已被自动隐藏'), findsOneWidget);
  });
}

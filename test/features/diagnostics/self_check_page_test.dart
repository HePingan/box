import 'dart:io';

import 'package:box/features/diagnostics/presentation/self_check_page.dart';
import 'package:box/features/extensions/plugins/net_diag/presentation/net_diag_page.dart';
import 'package:box/video/controller/video_catalog_repository.dart';
import 'package:box/video/models/video_category.dart';
import 'package:box/video/services/line_reachability_store.dart';
import 'package:box/utils/app_logger.dart';
import 'package:box/video_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「应用自检」页的用例。
///
/// 这个页最容易犯的错是"数字对不上还看不出来"（前身那两个死数字就是这么活了很久），
/// 所以每条都拿**真数据源**驱动一遍：片源数走 VideoController、隐藏数走 VideoModule
/// 的可见性记录、线路数走 LineReachabilityStore，然后按按钮再看它有没有真的变。
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
    hiveDir = await Directory.systemTemp.createTemp('box_self_check_hive_');
    Hive.init(hiveDir.path);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VideoModule.resetForTest();
    LineReachabilityStore.resetForTest();
    VideoController.resetPrefsCacheForTesting();
  });

  // AppLogger 每次写日志都会挂一个 flush 定时器；测试结束时定时器还挂着，
  // flutter_test 会报「A Timer is still pending…」。flush() 会先取消它。
  tearDown(() async => AppLogger.instance.flush());

  tearDownAll(() async {
    await Hive.close();
    if (hiveDir.existsSync()) await hiveDir.delete(recursive: true);
  });

  List<VideoSource> threeSources() => List.generate(
    3,
    (i) => VideoSource(
      id: 'src$i',
      name: '源$i',
      url: 'https://s$i.example.com/api.php/provide/vod/',
      detailUrl: '',
    ),
  );

  Future<VideoController> buildController({bool load = true}) async {
    final controller = VideoController(
      repository: _StubCatalogRepository(threeSources()),
    );
    if (load) {
      await controller.initSources('https://catalog.example.com/list.json');
    }
    addTearDown(controller.dispose);
    return controller;
  }

  /// 用例收尾：把两类定时器都收掉，否则 flutter_test 会在用例结束时报
  /// 「A Timer is still pending even after the widget tree was disposed」。
  /// - SnackBar 的自动消失定时器（本页两个按钮都会弹 SnackBar）；
  /// - AppLogger 每次写日志都会挂的 flush 定时器。
  Future<void> flushPendingTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await AppLogger.instance.flush();
  }

  Future<void> pumpPage(WidgetTester tester, VideoController controller) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<VideoController>.value(
        value: controller,
        child: const MaterialApp(home: SelfCheckPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('目录没加载就说"还没加载"，点【立即加载片源】之后变真数', (tester) async {
    final controller = await buildController(load: false);
    await pumpPage(tester, controller);

    expect(find.text('还没加载'), findsOneWidget);
    expect(find.text('立即加载片源'), findsOneWidget);

    await tester.tap(find.text('立即加载片源'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('3 个'), findsOneWidget, reason: '加载完要显示真数，不是 0');
    expect(find.text('还没加载'), findsNothing);
    await flushPendingTimers(tester);
  });

  testWidgets('被自动隐藏的源按可见性记录报数，【恢复】要连 failCount 一起归零', (tester) async {
    final controller = await buildController();
    final broken = controller.sources[1];
    await VideoModule.setSourceAutoHidden(broken, true, reason: '接口层不可用');

    await pumpPage(tester, controller);

    expect(find.text('1 个 · 源1'), findsOneWidget);
    // 恢复前：这就是 ① 在选源面板里显示的同一份记录。
    expect(VideoModule.getVisibilityRecord(broken).autoHidden, isTrue);

    await tester.tap(find.text('恢复全部被隐藏的源'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final record = VideoModule.getVisibilityRecord(broken);
    expect(record.autoHidden, isFalse, reason: '点完就该不再隐藏');
    expect(record.failCount, 0, reason: '计数不归零的话仍按"连续失败≥3"判不可用，等于没恢复');
    expect(find.text('无'), findsOneWidget);
    await flushPendingTimers(tester);
  });

  testWidgets('线路记忆按真实记录报数，【清空】之后归零', (tester) async {
    final controller = await buildController();
    await LineReachabilityStore.markFailure(
      sourceKey: 'src0',
      lineName: '线路A',
      reason: 'resolve 失败',
    );
    await LineReachabilityStore.markFailure(
      sourceKey: 'src0',
      lineName: '线路B',
      reason: 'resolve 失败',
    );

    await pumpPage(tester, controller);

    expect(find.text('2 条'), findsNWidgets(2), reason: '记住 2 条、其中 2 条最近取不到流');

    await tester.tap(find.text('清空线路记忆'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(LineReachabilityStore.records, isEmpty);
    expect(find.text('0 条'), findsNWidgets(2));
    await flushPendingTimers(tester);
  });

  testWidgets('更新通道：显示当前版本与更新地址，并给【检查更新】按钮', (tester) async {
    final controller = await buildController();
    await pumpPage(tester, controller);

    expect(find.text('更新通道'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(
      find.text('https://box.hpa888.top/api/v1/app-updates/check'),
      findsOneWidget,
      reason: '通道地址要如实显示（来自 AppConfig，不是写死的另一份）',
    );
    await flushPendingTimers(tester);
  });

  testWidgets('网络诊断：点进去是已有的 NetDiagPage，不是自造的第二套', (tester) async {
    final controller = await buildController();
    await pumpPage(tester, controller);

    // 网络诊断那张卡在首屏之下，先滚到它。
    await tester.scrollUntilVisible(
      find.text('打开网络诊断'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('打开网络诊断'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(NetDiagPage), findsOneWidget);
    await flushPendingTimers(tester);
  });
}

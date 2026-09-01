import 'dart:io';

import 'package:box/video/controller/video_catalog_repository.dart';
import 'package:box/video/controller/video_controller.dart';
import 'package:box/video/models/video_category.dart';
import 'package:box/video/models/video_source.dart';
import 'package:box/video/models/vod_item.dart';
import 'package:box/video/pages/aggregate_search_page.dart';
import 'package:box/video/services/video_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归：聚合搜索的 spinner 不得永久卡死。
///
/// 缺陷原形（aggregate_search_page.dart）：
///   - worker 的世代校验写在 `completed++` **之前**，旧世代 worker 直接 return；
///   - `_isLoading = false` 的唯一出口是 `completed == sources.length`；
///   - `_clearSearch()` 只自增世代，从不复位 `_isLoading`。
/// 于是「搜索途中点清空」会让 completed 永远补不齐，`_isLoading` 卡在 true ——
/// 而 spinner 与「正在聚合」文案都读它，用户可见。
///
/// 注意：本文件不能用 `pumpAndSettle()`。CircularProgressIndicator 是无限动画，
/// 缺陷未修时 settle 永不返回（实测卡死 8 分钟直到测试框架崩溃），
/// 那是超时而非断言失败。全部改用有界的 `pump(duration)`。
/// 全离线的目录仓库：`initSources` 会接着拉分类和首页列表，
/// 若不一并挡掉，测试会对 example.com 发真实请求并挂到超时。
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
    hiveDir = await Directory.systemTemp.createTemp('box_agg_search_hive_');
    Hive.init(hiveDir.path);
  });

  setUp(() {
    // VideoController.initSources 会 await SharedPreferences.getInstance()
    // 读「上次使用的源」。widget 测试里不 mock 会永久挂住（实测卡到超时，
    // 且卡在第一个 await 上，看起来像断言不执行）。
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // 关键：VideoController 用 static 字段缓存 SharedPreferences 的 future，
    // 而 future 会捕获创建它的 Zone。testWidgets 每个用例是独立 fakeAsync zone，
    // 第一个用例缓存下来后，第二个用例 await 到的是「已消失 zone」里的 future，
    // 回调永不调度 —— 表现为 initSources 静默挂死到超时（不报错、不打断言）。
    VideoController.resetPrefsCacheForTesting();
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDir.existsSync()) {
      await hiveDir.delete(recursive: true);
    }
  });

  tearDown(() {
    VideoApiService.searchOverrideForTesting = null;
  });

  Future<VideoController> buildController(int sourceCount) async {
    final sources = List.generate(
      sourceCount,
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
    // 断言失败会跳过函数尾部的 dispose()，泄漏的 controller 与在途 worker
    // 会把下一个测试一起拖死（实测：用例1失败后用例2挂到超时）。
    addTearDown(controller.dispose);
    return controller;
  }

  Widget wrap(VideoController controller) {
    return ChangeNotifierProvider<VideoController>.value(
      value: controller,
      child: const MaterialApp(home: AggregateSearchPage()),
    );
  }

  /// 提交搜索：SearchInputBar 的 TextField onSubmitted → onSubmit()。
  Future<void> submitSearch(WidgetTester tester, String keyword) async {
    await tester.enterText(find.byType(TextField).first, keyword);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
  }

  testWidgets('搜索途中点清空：spinner 必须停止，不得永久转圈', (tester) async {
    VideoApiService.searchOverrideForTesting = (baseUrl, keyword) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return <VodItem>[VodItem(vodId: 1, vodName: '$keyword-结果')];
    };

    final controller = await buildController(4);
    expect(
      controller.sources.where((s) => s.isAvailable).length,
      4,
      reason: '前置条件：必须有 4 个可用源，否则测不到多 worker 计数',
    );

    await tester.pumpWidget(wrap(controller));
    await tester.pump(const Duration(milliseconds: 100));

    await submitSearch(tester, '斗罗');

    expect(
      find.byType(CircularProgressIndicator),
      findsWidgets,
      reason: '搜索发起后应处于加载态',
    );

    // 搜索途中清空（作废在途 worker）。
    final state = tester.state<State>(find.byType(AggregateSearchPage));
    // ignore: avoid_dynamic_calls
    (state as dynamic).clearSearchForTesting();
    await tester.pump();

    // 等旧世代 worker 全部返回（300ms）再留余量，全程有界 pump。
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: '清空搜索后 _isLoading 必须复位，spinner 不得永久卡死',
    );
    expect(find.text('正在聚合'), findsNothing, reason: '清空后不应继续显示「正在聚合」');
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('搜索途中改词二次搜索：旧世代不得吞掉计数，最终必须收敛', (tester) async {
    var call = 0;
    VideoApiService.searchOverrideForTesting = (baseUrl, keyword) async {
      call++;
      final slow = keyword == '斗罗';
      await Future<void>.delayed(Duration(milliseconds: slow ? 400 : 50));
      return <VodItem>[VodItem(vodId: call, vodName: '$keyword-结果')];
    };

    final controller = await buildController(4);
    await tester.pumpWidget(wrap(controller));
    await tester.pump(const Duration(milliseconds: 100));

    await submitSearch(tester, '斗罗');
    await tester.pump(const Duration(milliseconds: 50));

    // 第一批还没回来就改词重搜。
    await submitSearch(tester, '遮天');

    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: '二次搜索完成后 spinner 必须停止（旧世代 worker 不得吞掉 completed 计数）',
    );
  }, timeout: const Timeout(Duration(seconds: 45)));
}

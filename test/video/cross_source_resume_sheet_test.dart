import 'dart:io';

import 'package:box/video/services/cross_source_resume.dart';
import 'package:box/video/widgets/cross_source_resume_sheet.dart';
import 'package:box/video_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 换源面板的接线：找到 → 面板自己关掉，把用户带进新片源的详情页（带上剧集名与进度）；
/// 没找到 → 不跳页，把「找过几个源」如实写在面板里。
///
/// 找片器本体在 `cross_source_resume_test.dart` 里单测；这里只钉 UI 接线 ——
/// 所以用 `searchOverride` 让「找片器是真的、网络是假的」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDir;

  setUpAll(() async {
    // 详情页一被 push 就会开 Hive（线路记忆 / 收藏），测试里得先把盒子备好，
    // 否则报「You need to initialize Hive」——那是测试环境问题，不是接线问题。
    hiveDir = await Directory.systemTemp.createTemp('box_csr_sheet_hive_');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDir.existsSync()) await hiveDir.delete(recursive: true);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VideoModule.resetForTest();
  });

  const source = VideoSource(
    id: 'a.com',
    name: '🎬甲源',
    url: 'https://a.com/api.php/provide/vod',
    detailUrl: '',
  );

  Future<void> openSheet(
    WidgetTester tester,
    CrossSourceMovieFinder finder,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    showCrossSourceResumeSheet(
      ctx,
      sources: const [source],
      request: const CrossSourceResumeRequest(
        vodName: '欢迎来龙餐馆',
        episodeName: 'HD中字',
        position: 12000,
      ),
      finder: finder,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('找到片源：面板关掉并把用户带进那家的详情页', (tester) async {
    final finder = CrossSourceMovieFinder(
      concurrency: 1,
      searchOverride: (s, keyword) async => [
        VodItem(vodId: 101, vodName: '欢迎来龙餐馆'),
      ],
    );

    await openSheet(tester, finder);
    await tester.pump(const Duration(milliseconds: 300));

    final page = tester.widget<VideoDetailPage>(find.byType(VideoDetailPage));
    expect(page.source.id, 'a.com');
    expect(page.vodId, 101, reason: '要用新片源自己的 vodId，不能用旧源的');
    expect(page.initialEpisodeName, 'HD中字', reason: '跨源续播靠剧集名认同一集');
    expect(page.initialPosition, 12000);
    expect(find.text('换源找片'), findsNothing, reason: '面板该关掉');
  });

  testWidgets('没找到：留在面板里如实说明，不跳页', (tester) async {
    final finder = CrossSourceMovieFinder(
      concurrency: 1,
      searchOverride: (s, keyword) async => const <VodItem>[],
    );

    await openSheet(tester, finder);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(VideoDetailPage), findsNothing);
    expect(find.textContaining('都没有《欢迎来龙餐馆》'), findsOneWidget);
    expect(find.text('知道了'), findsOneWidget);
  });

  testWidgets('一个可用源都没有：说清「不是没这部片，是没有源」', (tester) async {
    // 把唯一的源标记成自动隐藏 → 找片器没有候选源
    await VideoModule.setSourceAutoHidden(source, true, reason: '接口层不可用');

    final finder = CrossSourceMovieFinder(
      concurrency: 1,
      searchOverride: (s, keyword) async => const <VodItem>[],
    );

    await openSheet(tester, finder);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('当前没有可用的片源'), findsOneWidget);
  });
}

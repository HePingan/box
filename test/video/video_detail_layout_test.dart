import 'dart:io';

import 'package:box/video/models/video_source.dart';
import 'package:box/video/models/vod_item.dart';
import 'package:box/video/pages/detail/detail_info_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 详情页观感优化的护栏。
///
/// 起因：真机截图被指「看着很别扭」，逐处对齐后发现三个具体问题 ——
/// ① 单片时标题下「正在播放 · X」与唯一那个橙色剧集胶囊重复；
/// ② 「线路」行有图标+文字、剧集行直接铺满，两行起点差约 54px；
/// ④ 影片资料每行一个浅灰描边方框、值一律 w900，像方块阵又重。
///
/// 这类问题不会让测试变红，只能靠**结构性断言**防回退：
/// 结构断言（间距/对齐/重复）用源码与渲染树验证，不靠感觉。
void main() {
  String readLib(String path) => File('lib/$path').readAsStringSync();

  const source = VideoSource(
    id: 'quantum',
    name: '量子资源',
    url: 'https://example.com/api.php/provide/vod/',
    detailUrl: 'https://example.com/api.php/provide/vod/',
  );

  VodItem buildDetail() => VodItem(
    vodId: 1,
    vodName: '欢迎来龙餐馆',
    typeName: '战争片',
    vodRemarks: 'HD',
    vodTime: '2026-08-31 09:10:07',
    vodArea: '中国大陆',
    vodLang: '汉语普通话,阿拉伯语',
    vodDirector: '文牧野',
    vodContent: '剧情简介第一段。\n剧情简介第二段。',
  );

  group('④ 影片资料改成一张表（不再是一排方框）', () {
    Future<void> pumpCard(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DetailInfoCard(detail: buildDetail(), source: source),
            ),
          ),
        ),
      );
    }

    testWidgets('⑥ 不再出现「来源」行（资源名只在顶部标题卡说一次）', (tester) async {
      await pumpCard(tester);
      expect(find.textContaining('来源'), findsNothing);
      expect(find.textContaining('量子资源'), findsNothing);
    });

    testWidgets('标签不带全角冒号，值渲染在标签右侧', (tester) async {
      await pumpCard(tester);
      expect(find.text('分类'), findsOneWidget);
      expect(find.text('分类：'), findsNothing);
      expect(find.text('战争片'), findsOneWidget);
      expect(find.text('导演'), findsOneWidget);
      expect(find.text('文牧野'), findsOneWidget);
    });

    testWidgets('行与行之间用 1px 分隔线：n 行 → n-1 条线', (tester) async {
      await pumpCard(tester);
      // 本用例的数据有 5 行：分类 / 更新 / 时间 / 地区·语言 / 导演（无主演）。
      final dividers = tester
          .widgetList<Divider>(find.byType(Divider))
          .where((d) => d.thickness == 1)
          .toList();
      expect(dividers.length, 4);
    });

    testWidgets('值的字重不再是 w900（方块阵之外的另一半「重」）', (tester) async {
      await pumpCard(tester);
      final value = tester.widget<Text>(find.text('战争片'));
      expect(value.style?.fontWeight, isNot(FontWeight.w900));
      expect(value.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('④ 长值允许两行，「主演」不再只剩下前两个名字', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DetailInfoCard(
                detail: VodItem(
                  vodId: 2,
                  vodName: '欢迎来龙餐馆',
                  vodActor: '沈腾,蒋奇明,奥马尔·谢里夫,李治廷,王传君,张子枫',
                ),
                source: source,
              ),
            ),
          ),
        ),
      );
      final actor = tester.widget<Text>(find.textContaining('沈腾'));
      expect(actor.maxLines, 2);
    });
  });

  group('② / ⑦ 详情页源码结构护栏', () {
    test('线路行与剧集行都用 _LabeledRow：两行内容同一起点', () {
      final page = readLib('video/pages/video_detail_page.dart');
      expect(
        RegExp(r"_LabeledRow\(\s*label: '线路'").hasMatch(page),
        isTrue,
        reason: '线路行必须走 _LabeledRow，否则又和剧集行错开',
      );
      expect(
        RegExp(r"_LabeledRow\(\s*label: '剧集'").hasMatch(page),
        isTrue,
        reason: '剧集行必须走 _LabeledRow，否则又和线路行错开',
      );
    });

    test('⑦ 顶部不再用「全部线路集数之和」当集数', () {
      final page = readLib('video/pages/video_detail_page.dart');
      expect(
        page.contains(r'$totalEpisodes'),
        isFalse,
        reason: '那是最容易和单条线路集数对不上的写法（单片会被写成 2 集）',
      );
      expect(
        page.contains(r'fold<int>'),
        isFalse,
        reason: '集数求和的老写法应已删除，需要集数时按当前线路算',
      );
    });

    test('① 单片时不再显示「正在播放 · 」副标题', () {
      final page = readLib('video/pages/video_detail_page.dart');
      expect(
        page.contains('if (!isSingleEpisode) ...['),
        isTrue,
        reason: '副标题必须挂在非单片分支下，单片时那个橙色胶囊本身就是「正在播放」',
      );
    });

    test('③ 线路 chip 行高与剧集胶囊接近（34，而不是 42）', () {
      final page = readLib('video/pages/video_detail_page.dart');
      expect(
        RegExp(r'height: 34,').hasMatch(page),
        isTrue,
        reason: '线路 chip 行高应回到 34，别又变回那个空荡的 42',
      );
    });
  });

  group('第二轮（①②③④⑤⑥⑦）护栏', () {
    test('① 同一屏只留一个刷新入口：选集卡那个已删', () {
      final page = readLib('video/pages/video_detail_page.dart');
      final refreshIcons = RegExp(r'Icons\.refresh_rounded').allMatches(page);
      expect(
        refreshIcons.length,
        2,
        reason:
            '剩下的两个应该只有：顶部导航的刷新、错误页的「重试」；'
            '选集卡右上角那个和顶部是同一个动作，不该再出现',
      );
    });

    test('② 三处卡片标题都走 AppSectionTitle', () {
      expect(
        readLib(
          'video/pages/video_detail_page.dart',
        ).contains("AppSectionTitle('选集')"),
        isTrue,
        reason: '选集标题要和影片资料/剧情简介同一套样式',
      );
      expect(
        readLib(
          'video/pages/detail/detail_info_card.dart',
        ).contains('AppSectionTitle'),
        isTrue,
      );
    });

    test('③ 区块间距用 token，不再散落 10/12/36', () {
      final page = readLib('video/pages/video_detail_page.dart');
      expect(RegExp(r'SizedBox\(height: 36\)').hasMatch(page), isFalse);
      expect(page.contains('AppTokens.spaceMd'), isTrue);
      expect(page.contains('AppTokens.space2xl'), isTrue);
    });

    test('⑦ 播放器与卡片圆角统一 20', () {
      final page = readLib('video/pages/video_detail_page.dart');
      expect(
        RegExp(r'BorderRadius\.circular\(22\)').hasMatch(page),
        isFalse,
        reason: '播放器外壳的 22 已并入 20',
      );
    });
  });

  /// ② 线路「最近取不到流」要在**点进去之前**看出来，且默认不落在它上面。
  /// 行为判据在 `test/video/line_reachability_test.dart`；这里只钉界面接线，
  /// 免得哪天重构把标注或默认跳过的落点弄丢（这两处都在私有 State 里）。
  group('② 线路可用性前置标注', () {
    test('线路 chip 带「取不到流」标记，且标注仍可点（不是禁用）', () {
      final page = readLib('video/pages/video_detail_page.dart');
      expect(page.contains('unreachable: isUnreachable(index)'), isTrue);
      expect(page.contains('Icons.wifi_off_rounded'), isTrue);
      // chip 仍然把 onTap 传下去 —— 标记是前置告知，不拦用户手动选。
      expect(page.contains('onTap: () => onSelected(index)'), isTrue);
      expect(
        readLib(
          'video/pages/video_detail_page.dart',
        ).contains('child: InkWell('),
        isTrue,
        reason: '_PlaybackChip 用 InkWell 承载点击，标注不改变可点性',
      );
    });

    test('详情页把「最近取不到流」判据接进 chip 行', () {
      final page = readLib('video/pages/video_detail_page.dart');
      expect(
        page.contains('isUnreachable: controller.isLineRecentlyUnreachable'),
        isTrue,
      );
    });

    test('默认选线跳过被标记的线路，但全被标记时忽略标记', () {
      final controller = readLib(
        'video/controller/video_detail_controller.dart',
      );
      expect(controller.contains('_isLineUnreachable(lines[index])'), isTrue);
      expect(
        controller.contains(
          'final candidates = fresh.isEmpty ? playable : fresh;',
        ),
        isTrue,
        reason: '全被标记时要退回原判据，别把用户锁死',
      );
    });

    test('线路记忆不阻塞详情加载（不得在 loadDetail 里 await 存储）', () {
      final controller = readLib(
        'video/controller/video_detail_controller.dart',
      );
      expect(
        controller.contains('await LineReachabilityStore.ensureLoaded()'),
        isFalse,
        reason: '存储慢一步会把详情页永远停在 loading（实测 pumpAndSettle 超时）',
      );
      expect(
        controller.contains('unawaited(LineReachabilityStore.ensureLoaded())'),
        isTrue,
      );
    });
  });
}

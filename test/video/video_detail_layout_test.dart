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

  final source = const VideoSource(
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
}

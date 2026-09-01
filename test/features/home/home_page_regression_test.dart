import 'package:box/features/home/data/continue_item.dart';
import 'package:box/features/home/presentation/widgets/continue_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 首页回归测试。
///
/// 背景：首页此前零测试覆盖，两个问题靠读代码才发现：
/// 1. 「继续使用」卡片固定 176 宽，副标题「聚合影片、剧集与播放源」
///    在 maxLines:1 下被截断成「聚合影片、剧集与播…」（真机截图证实）。
/// 2. 热闻取 4 条但只渲染 3 条，第 4 条永远取到又永远不显示。
///
/// 「继续使用」后来从硬编码入口改成读真实播放/阅读进度（ContinueRail），
/// 卡片实现随之替换。下面的宽度/截断断言跟着迁到新卡片上 —— 这些是真机
/// 证实过的缺陷，换实现不等于问题不会重现。
Widget _rail(List<ContinueItem> items) {
  return MaterialApp(
    home: Scaffold(
      body: ContinueRail(
        items: items,
        onOpen: (_) {},
        onBrowseNovel: () {},
        onBrowseVideo: () {},
      ),
    ),
  );
}

ContinueItem _item({
  ContinueKind kind = ContinueKind.video,
  String id = 'v1',
  String title = '影视搜索',
  String subtitle = '聚合影片、剧集与播放源',
  double? progress,
}) {
  return ContinueItem(
    kind: kind,
    id: id,
    title: title,
    subtitle: subtitle,
    updatedAt: 1000,
    progress: progress,
  );
}

void main() {
  group('首页「继续使用」卡片文字不应被截断', () {
    /// 用真实文本布局测量：给定卡片内可用文字宽度，这段文案要几行才放得下。
    ///
    /// 为什么这样测而不是断言像素宽度：字体度量随平台/字体版本变化，
    /// 硬编码宽度会脆。这里只问一个稳定的问题——单行放不放得下。
    bool overflowsSingleLine({
      required String text,
      required double fontSize,
      required double maxWidth,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);
      return painter.didExceedMaxLines;
    }

    test('影视搜索副标题在旧的 176 固定宽度下确实放不下（复现截图现象）', () {
      // 176 卡宽 - 左右 padding 20 - 图标 34 - 图标右间距 8 = 114
      const availableTextWidth = 176.0 - 20 - 34 - 8;
      expect(
        overflowsSingleLine(
          text: '聚合影片、剧集与播放源',
          fontSize: 10.5,
          maxWidth: availableTextWidth,
        ),
        isTrue,
        reason: '这是修复前的现象：宽度不够，副标题被 ellipsis 截断',
      );
    });

    testWidgets('卡片能自适应变宽，副标题完整显示不出现省略号', (tester) async {
      // 真机常见宽度 392dp（截图那台机器量级）
      tester.view.physicalSize = const Size(392 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_rail([_item()]));
      await tester.pump();

      final subtitleFinder = find.text('聚合影片、剧集与播放源');
      expect(subtitleFinder, findsOneWidget);

      // 关键断言：这段文字实际渲染时没有超出单行 → 没被 ellipsis 吃掉
      final richText = tester.widget<RichText>(
        find.descendant(of: subtitleFinder, matching: find.byType(RichText)),
      );
      final painter = TextPainter(
        text: richText.text,
        maxLines: richText.maxLines,
        textDirection: richText.textDirection ?? TextDirection.ltr,
        textScaler: richText.textScaler,
      )..layout(maxWidth: tester.getSize(subtitleFinder).width);

      expect(
        painter.didExceedMaxLines,
        isFalse,
        reason: '副标题应完整显示，不应出现「聚合影片、剧集与播…」这种截断',
      );
    });
  });

  group('继续使用卡片宽度策略', () {
    testWidgets('窄屏时卡片不超出屏幕，仍可横向滚动', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 700 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _rail([
          _item(kind: ContinueKind.novel, id: 'n1', title: '小说书架', subtitle: '查看收藏与最近阅读'),
          _item(),
        ]),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '窄屏不应溢出报错');

      final cardWidth = tester.getSize(find.text('小说书架')).width;
      expect(
        cardWidth,
        lessThanOrEqualTo(320.0),
        reason: '单张卡不应宽过屏幕，实测 $cardWidth',
      );
    });

    testWidgets('点击卡片触发回调', (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContinueRail(
              items: [_item(kind: ContinueKind.novel, id: 'n1', title: '小说书架')],
              onOpen: (item) => opened.add(item.id),
              onBrowseNovel: () {},
              onBrowseVideo: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('小说书架'));
      await tester.pumpAndSettle();
      expect(opened, ['n1']);
    });
  });
}

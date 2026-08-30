import 'package:box/features/home/presentation/widgets/home_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 热闻空态/错误态的呈现契约。
///
/// 改版时发现的真实问题：拉取失败时代码把提示塞成一条 _NewsItem
/// （'网络异常，请稍后重试' / '暂无热点新闻，下拉刷新重试'），于是它被当成
/// 一条真新闻渲染——带项目符号、带右侧 chevron、还能点。点下去会打开
/// 一个 initialUrl 为 null 的 DailyNewsPage，是个死入口。
///
/// 这里钉住 HomeNewsLine 的能力：必须能表达「这不是一条可点的新闻」。
void main() {
  group('HomeNewsLine 提示态', () {
    testWidgets('提示态不显示可点击的 chevron 箭头', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeNewsLine(
              text: '网络异常，请稍后重试',
              showDivider: false,
              isPlaceholder: true,
            ),
          ),
        ),
      );

      expect(
        find.byIcon(Icons.chevron_right_rounded),
        findsNothing,
        reason: '提示文案不是可点的新闻，不应显示进入箭头，否则用户点了会打开空白页',
      );
    });

    testWidgets('正常新闻仍显示 chevron', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: HomeNewsLine(text: '一条真实热闻')),
        ),
      );

      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });

    testWidgets('提示态用次要文字色，弱化视觉重量', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeNewsLine(text: '暂无热点新闻，下拉刷新重试', isPlaceholder: true),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('暂无热点新闻，下拉刷新重试'));
      expect(
        text.style?.fontWeight,
        isNot(FontWeight.w600),
        reason: '提示文案不该和真新闻一样粗',
      );
    });
  });
}

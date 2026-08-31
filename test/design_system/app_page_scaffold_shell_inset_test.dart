// shellInset 的行为验证：确认它下发的是 padding.bottom，且不破坏
// 上方 SafeArea 的 top 处理，也不把可滚动体的 viewport 压小。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';

void main() {
  Future<void> pumpWithViewPadding(
    WidgetTester tester, {
    required double bottom,
    required bool shellInset,
    required Widget child,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          viewPadding: EdgeInsets.only(bottom: bottom, top: 24),
          padding: EdgeInsets.only(bottom: bottom, top: 24),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AppPageScaffold(shellInset: shellInset, child: child),
        ),
      ),
    );
  }

  testWidgets('shellInset 下发的 padding.bottom 等于 shellBottomInset', (
    tester,
  ) async {
    late double received;
    await pumpWithViewPadding(
      tester,
      bottom: 34,
      shellInset: true,
      child: Builder(
        builder: (context) {
          received = AppPageScaffold.bottomInsetOf(context);
          return const SizedBox();
        },
      ),
    );
    // shellBottomNavHeight 68 + viewPadding 34 + extra 28 = 130
    expect(received, 130);
  });

  testWidgets('未启用 shellInset 时不改动 padding', (tester) async {
    late double received;
    await pumpWithViewPadding(
      tester,
      bottom: 34,
      shellInset: false,
      child: Builder(
        builder: (context) {
          received = AppPageScaffold.bottomInsetOf(context);
          return const SizedBox();
        },
      ),
    );
    // SafeArea(bottom:false) 不消费 bottom，原样透传 34
    expect(received, 34);
  });

  testWidgets('shellInset 不缩小可滚动体的 viewport 高度', (tester) async {
    final key = GlobalKey();
    await pumpWithViewPadding(
      tester,
      bottom: 34,
      shellInset: true,
      child: ListView(
        key: key,
        children: const [SizedBox(height: 2000)],
      ),
    );
    final box = key.currentContext!.findRenderObject()! as RenderBox;
    // 顶部 SafeArea 消费 24，底部不消费 —— 高度应为 600 - 24
    expect(box.size.height, 600 - 24);
  });

  testWidgets('shellInset 与 maxContentWidth 可叠加', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(1200, 800),
          viewPadding: EdgeInsets.only(bottom: 20),
          padding: EdgeInsets.only(bottom: 20),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AppPageScaffold(
            shellInset: true,
            maxContentWidth: AppTokens.shellMaxContentWidth,
            child: SizedBox(key: key, height: 10),
          ),
        ),
      ),
    );
    final box = key.currentContext!.findRenderObject()! as RenderBox;
    expect(box.size.width, AppTokens.shellMaxContentWidth);
  });
}

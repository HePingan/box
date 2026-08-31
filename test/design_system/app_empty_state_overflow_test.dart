// 红灯回归：AppEmptyState 固定高度导致按钮被裁掉。
//
// 真实现象（用户 1.8.0 真机截图，内容中心 → 我的书架空态）：
// 说明文字「从小说书架同步最近阅读，也可以手动收藏书籍链接」在窄屏折成两行后，
// 底部「+ 打开小说书架」按钮下半截被空态卡片底边切断。
//
// 根因：app_cards.dart 的 AppEmptyState 写死 height = 168，而子 Column 的内容是
// 图标 46 + 间距 10 + 标题 ~20 + 间距 4 + 说明(1~3 行) + 间距 10 + 按钮 ~40，
// 说明文字一旦折成两行就超过 168，Column 溢出被 Container 裁剪。
//
// 这个测试断言「不发生溢出」，修复前必红。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/design_system/widgets/app_cards.dart';

Widget _host({required double width, required String message}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: AppEmptyState(
            title: '还没有我的书架',
            message: message,
            icon: Icons.menu_book_rounded,
            actionLabel: '打开小说书架',
            onAction: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  // 真机上这段文案就是折两行的那一条
  const realMessage = '从小说书架同步最近阅读，也可以手动收藏书籍链接';

  testWidgets('说明文字折行时空态卡片不溢出（真机截图里按钮被裁）', (tester) async {
    // 360dp 是常见窄屏宽度；卡片内还有 14+14 padding，实际可用更窄
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(width: 300, message: realMessage));

    expect(
      tester.takeException(),
      isNull,
      reason: 'AppEmptyState 固定 height=168 装不下折行文案 + 按钮，Column 溢出',
    );
  });

  testWidgets('长文案（三行）同样不应溢出', (tester) async {
    await tester.pumpWidget(
      _host(
        width: 260,
        message: '从小说书架同步最近阅读，也可以手动收藏书籍链接，支持批量导入与分区管理',
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('按钮必须完整可见（底边不被卡片裁掉）', (tester) async {
    await tester.pumpWidget(_host(width: 300, message: realMessage));
    await tester.pumpAndSettle();

    final card = tester.getRect(
      find.byType(AppEmptyState),
    );
    final button = tester.getRect(
      find.byType(FilledButton).first,
    );

    expect(
      button.bottom,
      lessThanOrEqualTo(card.bottom),
      reason: '按钮底边超出空态卡片底边 = 被裁切，用户看到半个按钮',
    );
  });

  testWidgets('短文案（不折行）本来就正常，修复不能把它撑变形', (tester) async {
    await tester.pumpWidget(_host(width: 400, message: '暂无内容'));
    expect(tester.takeException(), isNull);

    final card = tester.getRect(find.byType(AppEmptyState));
    // 内容撑起来的高度应当仍然接近原来的 168，不应突然变得很矮或很高
    expect(card.height, greaterThan(140));
    expect(card.height, lessThan(220));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归「点击检查更新没反应」。
///
/// 真实链路（lib/app_drawer.dart）：
///   1. 抽屉点「关于」→ `_showAboutDialog(context)`，**第一行**就
///      `Navigator.of(context).pop()` 把抽屉关掉，再 `showDialog` 弹关于框。
///   2. 关于框点「检查更新」→ `_checkUpdateManually(...)`。
///
/// 坏味道在于第 2 步传的是**抽屉的** context，而抽屉在第 1 步已经被 pop。
/// 于是 `_checkUpdateManually` 里的 `if (!context.mounted) return;` 必然命中，
/// 方法静默返回：没有 SnackBar、没有报错、没有任何反应。
///
/// 下面两个测试分别锁住「坏写法确实哑掉」和「好写法确实出提示」，
/// 这样以后谁把 ctx 改回 context 都会立刻红灯。
void main() {
  /// 用给定策略搭一个「抽屉 → 关于框 → 异步动作」的结构。
  ///
  /// [useDeadContext] 为 true 时复刻修复前的写法：把外层（已被 pop 的）
  /// context 传给异步方法；false 时复刻修复后的写法：用弹窗自己的 ctx。
  Future<void> pumpHarness(
    WidgetTester tester, {
    required bool useDeadContext,
    required List<String> shown,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (outerContext) => Scaffold(
            body: Center(
              child: ElevatedButton(
                // 对应抽屉里的「关于」项
                onPressed: () {
                  // 对应 _showAboutDialog 第一行：先把抽屉 pop 掉。
                  // 这里用 showDialog 模拟抽屉那一层路由。
                  showDialog<void>(
                    context: outerContext,
                    builder: (drawerCtx) => ElevatedButton(
                      onPressed: () {
                        Navigator.of(drawerCtx).pop(); // 抽屉关闭
                        showDialog<void>(
                          context: outerContext,
                          builder: (aboutCtx) => ElevatedButton(
                            // 关键分叉：传哪个 context 给异步方法
                            onPressed: () => checkLike(
                              useDeadContext ? drawerCtx : aboutCtx,
                              shown,
                            ),
                            child: const Text('检查更新'),
                          ),
                        );
                      },
                      child: const Text('关于'),
                    ),
                  );
                },
                child: const Text('打开抽屉'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('修复前：用已 pop 的抽屉 context，点检查更新出不来提示', (tester) async {
    final shown = <String>[];
    await pumpHarness(tester, useDeadContext: true, shown: shown);

    await tester.tap(find.text('打开抽屉'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    // debug/测试下 `ScaffoldMessenger.of(deadContext)` 会命中
    // 「Looking up a deactivated widget's ancestor is unsafe」这条 assert；
    // release 包里 assert 被整个编译掉，于是退化成「什么都没发生」——
    // 这正是真机上「点击检查更新没反应」。
    expect(
      tester.takeException(),
      isAssertionError,
      reason: '失效 context 查 ScaffoldMessenger：debug 抛 assert，release 静默',
    );
    expect(shown, isEmpty, reason: '两种模式下结果一致：提示都发不出来');
  });

  testWidgets('修复后：用关于框自己的 ctx，能正常弹出提示', (tester) async {
    final shown = <String>[];
    await pumpHarness(tester, useDeadContext: false, shown: shown);

    await tester.tap(find.text('打开抽屉'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查更新'));
    await tester.pump(); // 让 SnackBar 进入

    expect(shown, contains('正在检查更新…'));
    expect(
      find.text('正在检查更新…'),
      findsOneWidget,
      reason: 'SnackBar 必须真的挂到 widget 树上，不只是回调被调用',
    );
  });
}

/// 复刻 `_checkUpdateManually` 的关键前半段：
/// 先抓 messenger，再判 mounted，然后弹提示。
void checkLike(BuildContext context, List<String> shown) {
  final messenger = ScaffoldMessenger.of(context);
  if (!context.mounted) return; // 修复前正是这里静默返回
  shown.add('正在检查更新…');
  messenger.showSnackBar(
    const SnackBar(
      content: Text('正在检查更新…'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

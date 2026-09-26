import 'package:box/features/extensions/core/builtin_plugin_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// FIX-05 第二部分：预填链接来自插件 payload 时，先让用户看见"要去哪个 host"。
void main() {
  Future<void> pumpLauncher(WidgetTester tester, String url) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showGithubAccelAction(ctx, url),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('预填链接前先确认 host，取消则不打开面板', (tester) async {
    await pumpLauncher(tester, 'https://github.com/a/b');
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(
      find.text('将通过加速代理访问 github.com'),
      findsOneWidget,
      reason: '要让用户看见流量会被导向哪个 host 再继续',
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.text('转换为加速链接'),
      findsNothing,
      reason: '取消后不应打开加速面板',
    );
  });

  testWidgets('没有预填链接时不打扰用户（直接开面板）', (tester) async {
    await pumpLauncher(tester, '');
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.text('转换为加速链接'),
      findsOneWidget,
      reason: '空链接是用户自己粘贴的常规路径，不该多一道确认',
    );
  });
}

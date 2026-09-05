import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/app_drawer.dart';
import 'package:box/features/cloud_sync/domain/announcement_center.dart';

/// 用户报障原文：「更新清单签名校验未通过(HMAC 更新验签缺少 secret) 这个提示
/// 在最下层，关闭侧边栏才能看到」。
///
/// 抽屉是覆盖在主页面之上的一层，而 SnackBar 由 ScaffoldMessenger 挂在主页面
/// 底部。从抽屉里点「检查更新」，结果就压在抽屉底下 —— 用户以为没反应，
/// 关掉抽屉才发现有一条已经快消失的提示。
///
/// 结论性反馈必须落在用户当前看得见的那一层：改用对话框。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Box',
      packageName: 'top.hpa888.box',
      version: '1.9.9',
      buildNumber: '199',
      buildSignature: '',
    );
  });

  Future<void> pumpDrawer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AnnouncementCenter>.value(
        value: AnnouncementCenter(),
        child: const MaterialApp(
          home: Scaffold(drawer: AppDrawer(), body: SizedBox.shrink()),
        ),
      ),
    );
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
  }

  testWidgets('从抽屉检查更新，结论显示在抽屉之上而不是被它盖住', (tester) async {
    await pumpDrawer(tester);

    await tester.ensureVisible(find.text('检查更新'));
    await tester.tap(find.text('检查更新'));
    // 网络在测试环境必然失败，走的正是用户碰到的失败分支。
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 失败结论必须以对话框呈现：对话框在 Navigator overlay 上，盖在抽屉之上。
    // 原实现用 SnackBar，它挂在主页面底部，会被抽屉整个盖住。
    expect(
      find.byType(AlertDialog),
      findsOneWidget,
      reason: '检查更新的结论要落在抽屉之上的一层，用户当场就能看到',
    );
    expect(
      find.textContaining('更新'),
      findsWidgets,
      reason: '对话框里应当写明这次检查的结论',
    );
  });

  testWidgets('结论框可以关掉，关掉后抽屉还在', (tester) async {
    await pumpDrawer(tester);

    await tester.ensureVisible(find.text('检查更新'));
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    expect(
      scaffold.isDrawerOpen,
      isTrue,
      reason: '关掉结论框应当回到抽屉，而不是把用户丢回主页面',
    );
  });
}

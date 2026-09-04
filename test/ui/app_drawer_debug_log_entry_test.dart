import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:box/app_drawer.dart';
import 'package:box/features/cloud_sync/domain/announcement_center.dart';
import 'package:box/pages/debug_log_page.dart';

/// 回归用例来源于真实反馈：用户被告知「侧边栏 → 调试日志」，
/// 但抽屉里根本没有这一项 —— 入口只藏在底部那行版本号的点击手势上，
/// 没有任何可见提示。普通用户（没有 adb）因此拿不到现场日志。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Box',
      packageName: 'top.hpa888.box',
      version: '1.9.4',
      buildNumber: '194',
      buildSignature: '',
    );
  });

  Future<void> pumpDrawer(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AnnouncementCenter>(
        create: (_) => AnnouncementCenter(),
        child: MaterialApp(
          routes: {'/debug-log': (_) => const DebugLogPage()},
          home: const Scaffold(drawer: AppDrawer(), body: SizedBox.shrink()),
        ),
      ),
    );
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
  }

  testWidgets('抽屉「更多」区列出可见的「调试日志」入口', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpDrawer(tester);

    expect(find.text('调试日志'), findsOneWidget);
  });

  testWidgets('点「调试日志」进得去日志页', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpDrawer(tester);

    await tester.ensureVisible(find.text('调试日志'));
    await tester.tap(find.text('调试日志'));
    await tester.pumpAndSettle();

    expect(find.byType(DebugLogPage), findsOneWidget);
  });

  testWidgets('底部版本号读真实包信息，不再硬编码 v2.0.0', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpDrawer(tester);

    expect(find.text('v2.0.0'), findsNothing);
    expect(find.text('v1.9.4+194'), findsOneWidget);
  });
}

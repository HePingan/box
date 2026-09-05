import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/app_drawer.dart';
import 'package:box/features/cloud_sync/domain/announcement_center.dart';
import 'package:box/features/settings/presentation/settings_page.dart';
import 'package:box/features/account/presentation/account_page.dart';
import 'package:box/pages/debug_log_page.dart';

/// 抽屉信息架构回归（A 阶段）。
///
/// 用户原话：「我感觉导航那几个是多余的」。读代码确认成立——
/// `app_shell.dart` 的 bottomNavigationBar 常驻同样这 4 个 tab，
/// 数据源是同一个 `_tabs`，抽屉那份是纯复制品，还多占约 150dp，
/// 把只能从抽屉进的功能挤到要滚动才看得到。
///
/// 另外两条是读代码发现、用户没提的真 bug：
///   - 「设置」和「账号中心」都跳 AppRoutes.account（同一个页面，两个入口）
///   - 底部版本号的隐藏点击手势与「更多」里的正式「调试日志」入口重复
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Box',
      packageName: 'top.hpa888.box',
      version: '1.9.6',
      buildNumber: '196',
      buildSignature: '',
    );
  });

  Future<void> pumpDrawer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AnnouncementCenter>(
        create: (_) => AnnouncementCenter(),
        child: MaterialApp(
          routes: {
            '/debug-log': (_) => const DebugLogPage(),
            '/settings': (_) => const SettingsPage(),
            '/account': (_) => const AccountPage(),
          },
          home: const Scaffold(drawer: AppDrawer(), body: SizedBox.shrink()),
        ),
      ),
    );
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
  }

  group('导航区冗余：底栏已常驻同样 4 项', () {
    testWidgets('抽屉不再出现「导航」分组标题', (tester) async {
      await pumpDrawer(tester);
      expect(find.text('导航'), findsNothing);
    });

    testWidgets('抽屉不再重复列出四个 tab 名', (tester) async {
      await pumpDrawer(tester);
      for (final name in ['首页', '工具', '内容', '扩展']) {
        expect(
          find.text(name),
          findsNothing,
          reason: '$name 已在底部导航栏常驻，抽屉里重复只是占高度',
        );
      }
    });
  });

  group('「设置」必须是独立页，不能再跳账号中心', () {
    testWidgets('点「设置」进设置页，而不是 AccountPage', (tester) async {
      await pumpDrawer(tester);

      await tester.ensureVisible(find.text('设置'));
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsPage), findsOneWidget);
      expect(
        find.byType(AccountPage),
        findsNothing,
        reason: '改之前这里跳的是 AppRoutes.account，与「账号中心」撞同一个页面',
      );
    });

    testWidgets('设置页含「通用设置」「数据设置」两组', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SettingsPage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('通用设置'), findsOneWidget);
      expect(find.text('数据设置'), findsOneWidget);
    });
  });

  group('「更多」分组：常用/数据/帮助', () {
    testWidgets('三个分组标题都在', (tester) async {
      await pumpDrawer(tester);
      for (final section in ['常用', '数据', '帮助']) {
        expect(find.text(section), findsOneWidget, reason: '缺分组标题：$section');
      }
    });

    testWidgets('公告与调试日志入口保留（此前修过的回归不能被这轮改掉）', (tester) async {
      await pumpDrawer(tester);
      expect(find.text('公告'), findsOneWidget);
      expect(find.text('调试日志'), findsOneWidget);
    });
  });

  group('底部版本号：撤掉隐藏手势', () {
    testWidgets('版本号仍显示真实包信息', (tester) async {
      await pumpDrawer(tester);
      expect(find.text('v2.0.0'), findsNothing);
      expect(find.text('v1.9.6+196'), findsOneWidget);
    });

    testWidgets('点版本号不再偷偷进调试日志', (tester) async {
      await pumpDrawer(tester);

      await tester.ensureVisible(find.text('v1.9.6+196'));
      await tester.tap(find.text('v1.9.6+196'));
      await tester.pumpAndSettle();

      expect(
        find.byType(DebugLogPage),
        findsNothing,
        reason: '「更多」里已有正式入口，隐藏路径留着只是多一条没人知道的路',
      );
    });
  });
}

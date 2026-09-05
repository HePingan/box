import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/app_drawer.dart';
import 'package:box/features/cloud_sync/domain/announcement_center.dart';
import 'package:box/features/settings/presentation/data_settings_page.dart';

/// 把两个「已经实现、但埋得太深」的功能提到该在的地方：
///
///  1. 「检查更新」原先只在「关于」框的 actions 里，用户得先点关于再点它。
///     这是会被主动寻找的动作（尤其是忽略过某版本之后唯一的找回入口），
///     提到抽屉「帮助」组。
///  2. 「清理缓存」实现在 personal_center_page.dart，埋在个人中心里。
///     它属于数据类操作，并进「数据设置」页。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Box',
      packageName: 'top.hpa888.box',
      version: '1.9.8',
      buildNumber: '198',
      buildSignature: '',
    );
  });

  Future<void> pumpDrawer(WidgetTester tester) async {
    // 宽视口避免关于框标题行 RenderFlex 溢出造成假红灯。
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

  group('「检查更新」提到抽屉「帮助」组', () {
    testWidgets('抽屉列表里直接能看到「检查更新」', (tester) async {
      await pumpDrawer(tester);
      expect(
        find.text('检查更新'),
        findsOneWidget,
        reason: '改之前它只藏在「关于」框的按钮里，抽屉列表上找不到',
      );
    });

    testWidgets('点它不会把身下的主页面 pop 掉', (tester) async {
      await pumpDrawer(tester);

      await tester.ensureVisible(find.text('检查更新'));
      await tester.tap(find.text('检查更新'));
      await tester.pump();

      // 「正在检查更新…」的 SnackBar 带 1s 定时器，不放它走完，
      // 测试结束时会因 pending timer 报错 —— 那是脚手架问题不是缺陷。
      await tester.pump(const Duration(seconds: 2));

      // _checkUpdateManually 在「有新版本」时会 navigator.pop() 关掉宿主
      // 关于框。从抽屉列表直接调用时，抽屉不是路由，那一下会 pop 掉底下的
      // 主页面。宿主关闭行为必须可参数化，不能写死 pop。
      expect(
        find.byType(Scaffold),
        findsWidgets,
        reason: '主页面不能被 pop 掉',
      );
    });

    testWidgets('「关于」框里仍保留检查更新，不搬走只是多一个入口', (tester) async {
      await pumpDrawer(tester);

      await tester.ensureVisible(find.text('关于'));
      await tester.tap(find.text('关于'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('检查更新'),
        ),
        findsOneWidget,
        reason: '老用户已经习惯在关于框里点它，不能悄悄搬走',
      );
    });
  });

  group('「清理缓存」并进数据设置页', () {
    testWidgets('数据设置页有「清理缓存」入口', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DataSettingsPage()));
      await tester.pumpAndSettle();

      expect(find.text('清理缓存'), findsOneWidget);
    });

    testWidgets('点「清理缓存」先弹确认框，说明不会删掉什么', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DataSettingsPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('清理缓存'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget, reason: '清缓存是破坏性操作，必须先确认');
      // 用户最怕的是「清缓存把我的书和题库清了」，确认文案必须讲清边界。
      expect(find.textContaining('不会删除'), findsOneWidget);
    });

    testWidgets('确认框里点「取消」不执行清理', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DataSettingsPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('清理缓存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('备份与恢复两项没被这轮改动挤掉', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DataSettingsPage()));
      await tester.pumpAndSettle();

      expect(find.text('备份本地数据'), findsOneWidget);
      expect(find.text('恢复本地数据'), findsOneWidget);
    });
  });
}

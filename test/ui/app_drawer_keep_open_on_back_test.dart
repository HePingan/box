import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/app_drawer.dart';
import 'package:box/app/app_routes.dart';
import 'package:box/features/about/presentation/about_page.dart';
import 'package:box/features/cloud_sync/domain/announcement_center.dart';
import 'package:box/features/settings/presentation/settings_page.dart';

/// 用户报的真实现象：
/// 「我点侧边栏的功能后，返回侧边栏他把侧边栏帮我关闭了，我还得重新打开侧边栏」
///
/// 根因不在返回逻辑，而在进入时：`_openRoute` 先 `pop()` 关抽屉再 push 目标页，
/// 于是从目标页返回时抽屉早已不存在。修法是先 push、等目标页返回后再关抽屉。
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
    // 关于框标题行在窄视口下会 RenderFlex overflow —— 那是测试脚手架的视口
    // 太窄，不是被测缺陷（真机 iQOO/红米都比这宽）。dpr 设 1.0 让
    // 物理像素直接等于逻辑 dp，给足 900dp 宽，避免假红灯干扰真实断言。
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AnnouncementCenter>.value(
        value: AnnouncementCenter(),
        child: MaterialApp(
          routes: {
            '/settings': (_) => const SettingsPage(),
            // 关于改成整页后必须注册，否则点「关于」抛路由异常。
            AppRoutes.about: (_) => const AboutPage(versionOverride: '1.9.8+198'),
          },
          home: const Scaffold(
            drawer: AppDrawer(),
            body: SizedBox.shrink(),
          ),
        ),
      ),
    );
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
  }

  testWidgets('从设置页返回后，侧边栏仍然是打开的', (tester) async {
    await pumpDrawer(tester);
    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    expect(scaffold.isDrawerOpen, isTrue, reason: '前置条件：抽屉已打开');

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget, reason: '已进入设置页');

    // 从设置页返回
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.pop();
    await tester.pumpAndSettle();

    expect(
      scaffold.isDrawerOpen,
      isTrue,
      reason: '返回后抽屉应当还在原位，用户不必重新划开',
    );
  });

  testWidgets('目标页正常打开，且盖在抽屉之上（抽屉留着是刻意的）', (tester) async {
    await pumpDrawer(tester);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    // 修好之后抽屉是刻意「留在身后」的，所以这里不能断言它已关闭——
    // 那正是要保留的状态。要保证的是目标页确实压在最上层，
    // 用户看到的是设置页而不是半透明遮罩下的抽屉。
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(
      find.text('通用设置'),
      findsOneWidget,
      reason: '设置页内容应当可见，说明它在最上层而非被抽屉遮住',
    );
  });

  testWidgets('从「关于」页返回后，侧边栏同样还在', (tester) async {
    // 原先「关于」是抽屉里的 AlertDialog，这条测的是关掉弹窗后抽屉还在。
    // 现在「关于」改成了整页（AppRoutes.about），断言随之改为"从页面返回后
    // 抽屉还在" —— 要防的毛病没变（先 pop 抽屉再打开目标，返回时抽屉已消失）。
    await pumpDrawer(tester);
    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);

    await tester.ensureVisible(find.text('关于'));
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutPage), findsOneWidget, reason: '关于页已打开');

    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.pop();
    await tester.pumpAndSettle();

    expect(
      scaffold.isDrawerOpen,
      isTrue,
      reason: '「关于」也走 _openRoute，同一个先 pop 抽屉的毛病不能复发',
    );
  });

  testWidgets('「检查更新」入口没丢：抽屉里有，关于页里也有', (tester) async {
    // 这条按钮曾因为传了已 pop 的抽屉 context 而静默无反应
    // （见 test/update/manual_check_snackbar_test.dart）。关于从弹窗改整页时
    // 动了同一段时序，必须确认入口没被弄丢。
    await pumpDrawer(tester);

    // 抽屉「帮助」组那条（忽略某版本后唯一的找回入口）
    expect(find.text('检查更新'), findsOneWidget);

    await tester.ensureVisible(find.text('关于'));
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();

    // 关于页里的镜像入口
    expect(
      find.descendant(
        of: find.byType(AboutPage),
        matching: find.text('检查更新'),
      ),
      findsOneWidget,
      reason: '关于页必须保留检查更新入口，用户习惯在这里找',
    );
  });
}

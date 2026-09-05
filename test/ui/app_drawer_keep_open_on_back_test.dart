import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/app_drawer.dart';
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
          routes: {'/settings': (_) => const SettingsPage()},
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

  testWidgets('关闭「关于」弹窗后，侧边栏同样还在', (tester) async {
    await pumpDrawer(tester);
    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);

    await tester.ensureVisible(find.text('关于'));
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    // 抽屉头部本来就写着「Geek工具箱 Pro」，不 pop 抽屉之后它与弹窗标题
    // 同时在树里，所以要限定在 AlertDialog 范围内找。
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Geek工具箱 Pro'),
      ),
      findsOneWidget,
      reason: '关于框已弹出',
    );

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(
      scaffold.isDrawerOpen,
      isTrue,
      reason: '「关于」也是先 pop 抽屉再弹框，同一个毛病',
    );
  });

  testWidgets('关于框里的「检查更新」按钮仍然存在（不能退回哑掉的老 bug）', (tester) async {
    await pumpDrawer(tester);

    await tester.ensureVisible(find.text('关于'));
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();

    // 这条按钮曾因为传了已 pop 的抽屉 context 而静默无反应
    // （见 test/update/manual_check_snackbar_test.dart）。本轮改动动了
    // 同一段 pop 时序，必须确认入口没被弄丢。
    //
    // 限定在 AlertDialog 内查找：抽屉「帮助」组现在也有一条「检查更新」，
    // 不限定范围会同时命中两个。
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('检查更新'),
      ),
      findsOneWidget,
    );
  });
}

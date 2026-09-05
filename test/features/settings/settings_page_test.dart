import 'package:box/app/app_routes.dart';
import 'package:box/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 用一个最小壳子承载设置页，并记录它试图跳转到哪个路由名。
  Widget host({required List<String> pushed}) {
    return MaterialApp(
      home: const SettingsPage(),
      onGenerateRoute: (settings) {
        pushed.add(settings.name ?? '');
        return MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('目标页')),
        );
      },
    );
  }

  group('设置页结构', () {
    testWidgets('渲染通用设置与数据设置两个分组', (tester) async {
      await tester.pumpWidget(host(pushed: []));

      expect(find.text('设置'), findsOneWidget);
      expect(find.text('通用设置'), findsOneWidget);
      expect(find.text('数据设置'), findsOneWidget);
    });

    testWidgets('深色模式与主题配色显示为暂不可用，并说明原因', (tester) async {
      await tester.pumpWidget(host(pushed: []));

      expect(find.text('深色模式'), findsOneWidget);
      expect(find.text('主题配色'), findsOneWidget);
      // 不能只标灰就完事，必须写清为什么不能点。
      expect(find.textContaining('暂不可用'), findsNWidgets(2));
    });

    testWidgets('点击停用项不触发任何跳转', (tester) async {
      final pushed = <String>[];
      await tester.pumpWidget(host(pushed: pushed));

      await tester.tap(find.text('深色模式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('主题配色'));
      await tester.pumpAndSettle();

      expect(pushed, isEmpty, reason: '停用项必须真的点不动');
    });
  });

  group('设置页跳转', () {
    testWidgets('「备份与恢复」跳到 AppRoutes.dataSettings', (tester) async {
      final pushed = <String>[];
      await tester.pumpWidget(host(pushed: pushed));

      await tester.tap(find.text('备份与恢复'));
      await tester.pumpAndSettle();

      expect(pushed, contains(AppRoutes.dataSettings));
    });

    testWidgets('跳转目标与 AppRoutes 常量保持同一个值', (tester) async {
      final pushed = <String>[];
      await tester.pumpWidget(host(pushed: pushed));

      await tester.tap(find.text('备份与恢复'));
      await tester.pumpAndSettle();

      // 页面里若写死 '/settings/data' 字面量，一旦 AppRoutes 改名就会
      // 静默失联；这里断言两者同源，改名时测试会先红。
      expect(pushed.single, AppRoutes.dataSettings);
      expect(AppRoutes.dataSettings, '/settings/data');
    });
  });
}

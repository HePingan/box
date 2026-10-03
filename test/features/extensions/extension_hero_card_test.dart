import 'package:box/features/extensions/presentation/widgets/extension_management_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 扩展页顶部那行数字必须都是**数得出来的**真数。
///
/// 前一版写的是「书源 / 片源 / 其它」三个 chip：片源计数是 `_videoSourceCount = 0;`
/// 硬写死的、书源计数读的两个 prefs key 全仓无人写，两个 0 活了很久没人发现。
/// 现在改成 插件总数 / 已启用 / 内置 / 第三方 —— 全部来自 `HomePlugin.builtIn`。
void main() {
  Future<void> pumpHero(
    WidgetTester tester, {
    required int pluginCount,
    required int enabledCount,
    required int builtInCount,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExtensionHeroCard(
            pluginCount: pluginCount,
            enabledCount: enabledCount,
            builtInCount: builtInCount,
            onOpenMarket: () {},
            onImportJson: () {},
            onExportJson: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('显示已启用/总数与内置/第三方，且不再出现那两个死数字', (tester) async {
    await pumpHero(tester, pluginCount: 20, enabledCount: 20, builtInCount: 18);

    expect(find.text('已启用 20 / 共 20'), findsOneWidget);
    expect(find.text('内置 18 · 第三方 2'), findsOneWidget);
    expect(find.textContaining('书源'), findsNothing);
    expect(find.textContaining('片源'), findsNothing);
  });

  testWidgets('全部内置时第三方为 0（不是空白、不隐藏这一行）', (tester) async {
    await pumpHero(tester, pluginCount: 20, enabledCount: 12, builtInCount: 20);

    expect(find.text('已启用 12 / 共 20'), findsOneWidget);
    expect(find.text('内置 20 · 第三方 0'), findsOneWidget);
  });
}

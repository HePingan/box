// 「我的收藏」区块的接线验证。
//
// 领域层全绿不代表 UI 接对了：仍然可能忘了刷新列表、把校验只做在 store 里
// 而对话框放行、或者删除没有确认。这里走真实 widget 树。
library;

import 'package:box/features/tools/domain/custom_site_store.dart';
import 'package:box/features/tools/presentation/widgets/custom_site_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host() => const MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: CustomSiteSection())),
);

void main() {
  late Map<String, String> fakePrefs;

  setUp(() {
    fakePrefs = <String, String>{};
    CustomSiteStore.readRaw = () async => fakePrefs[CustomSiteStore.prefsKey];
    CustomSiteStore.writeRaw = (raw) async {
      fakePrefs[CustomSiteStore.prefsKey] = raw;
    };
  });

  tearDown(CustomSiteStore.resetHooksForTest);

  testWidgets('空库时给出引导文案，不是空白区块', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.textContaining('添加你常用的网站'), findsOneWidget);
  });

  testWidgets('通过 ＋ 添加网站后，列表立刻出现该条目', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加网站'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, '网址'),
      'photopea.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '名称（留空则用域名）'),
      '在线PS',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('在线PS'), findsOneWidget);
    // 规范化后的地址要显示出来，用户才看得出自己存了什么。
    expect(find.text('https://photopea.com'), findsOneWidget);
    // 也必须真的落盘，否则重进页面就没了。
    expect(fakePrefs[CustomSiteStore.prefsKey], contains('photopea.com'));
  });

  testWidgets('危险 scheme 在对话框就被拦下，不写入存储', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加网站'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, '网址'),
      'javascript://evil.com/%0aalert(1)',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    // 对话框仍在（校验没过），且什么都没存。
    expect(find.text('请填写有效的 http/https 网址'), findsOneWidget);
    expect(fakePrefs[CustomSiteStore.prefsKey], isNull);
  });

  testWidgets('删除需要确认；确认后条目消失', (tester) async {
    await CustomSiteStore().add(title: '示例站', url: 'example.com');

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.text('示例站'), findsOneWidget);

    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    // 必须先问一句，不能一点就没。
    expect(find.text('删除收藏'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('示例站'), findsOneWidget, reason: '取消后不该删除');

    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('示例站'), findsNothing);
  });

  testWidgets('计数随条目数更新', (tester) async {
    final store = CustomSiteStore();
    await store.add(title: 'A', url: 'a.com');
    await store.add(title: 'B', url: 'b.com');

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('2 个网站'), findsOneWidget);
  });
}

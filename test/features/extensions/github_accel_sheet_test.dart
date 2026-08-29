import 'package:box/features/extensions/plugins/github_accel/github_accel_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 面板的 UI 契约。
///
/// 不测真实下载（需要网络），只锁：预填链接能自动转换出加速地址、
/// 镜像切换会重算、非法输入给出提示、复制按钮把加速链接写进剪贴板。
void main() {
  const stable =
      'https://github.com/kelai141/dsh-mobile-apk/releases/latest/download/'
      'dsh-mobile-apk-v0.13.0-fx-1-arm64.apk';

  Future<void> pump(WidgetTester tester, {String url = ''}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GithubAccelSheet(initialUrl: url)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('预填稳定链接时自动转换出加速地址', (tester) async {
    await pump(tester, url: stable);

    expect(find.text('转换成功'), findsOneWidget);
    expect(
      find.text('https://gh-proxy.com/$stable'),
      findsOneWidget,
      reason: '不联网就能转换的形态，打开面板即应产出结果',
    );
  });

  testWidgets('转换成功后出现下载与复制按钮', (tester) async {
    await pump(tester, url: stable);

    expect(find.widgetWithText(FilledButton, '立即下载'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '复制'), findsOneWidget);
  });

  testWidgets('复制按钮把加速链接写入剪贴板', (tester) async {
    final writes = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          writes.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await pump(tester, url: stable);
    await tester.tap(find.widgetWithText(OutlinedButton, '复制'));
    await tester.pumpAndSettle();

    expect(writes.single, 'https://gh-proxy.com/$stable');
  });

  testWidgets('切换镜像会重算加速地址', (tester) async {
    await pump(tester, url: stable);
    expect(find.text('https://gh-proxy.com/$stable'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'ghfast.top'));
    await tester.pumpAndSettle();

    expect(find.text('https://ghfast.top/$stable'), findsOneWidget);
    expect(find.text('https://gh-proxy.com/$stable'), findsNothing);
  });

  testWidgets('非 GitHub 链接给出无法转换提示', (tester) async {
    await pump(tester, url: 'https://example.com/a.apk');

    expect(find.text('无法转换'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '立即下载'), findsNothing);
  });

  testWidgets('空输入时不显示结果卡片', (tester) async {
    await pump(tester);

    expect(find.text('转换成功'), findsNothing);
    expect(find.text('无法转换'), findsNothing);
    expect(find.widgetWithText(FilledButton, '转换为加速链接'), findsOneWidget);
  });

  testWidgets('已加速链接原样保留且提示不要二次包装', (tester) async {
    await pump(tester, url: 'https://gh-proxy.com/$stable');

    expect(find.text('转换成功'), findsOneWidget);
    // 输入框和结果区文本相同，只断言结果区那一处
    expect(
      find.descendant(
        of: find.byType(SelectableText),
        matching: find.text('https://gh-proxy.com/$stable'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('已经是加速地址'),
      findsOneWidget,
      reason: '要主动告知，否则用户会以为没生效而重复粘贴',
    );
  });

  testWidgets('显示解析出的文件名', (tester) async {
    await pump(tester, url: stable);
    expect(
      find.text('dsh-mobile-apk-v0.13.0-fx-1-arm64.apk'),
      findsOneWidget,
    );
  });

  testWidgets('帮助区列出支持的链接形态', (tester) async {
    await pump(tester);
    expect(find.text('支持的链接形态'), findsOneWidget);
    expect(find.textContaining('raw.githubusercontent.com'), findsOneWidget);
  });

  testWidgets('四个内置镜像都渲染成可选项', (tester) async {
    await pump(tester);
    expect(find.byType(ChoiceChip), findsNWidgets(4));
  });
}

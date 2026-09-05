import 'package:box/pages/debug_log_page.dart';
import 'package:box/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLogger.instance.lines.value = const <String>[];
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: DebugLogPage()));
    await tester.pumpAndSettle();
  }

  void seed() {
    AppLogger.instance.lines.value = List<String>.unmodifiable([
      '[2026-09-05T10:00:00.000][PLAYER][I] 播放起播',
      '[2026-09-05T10:00:01.000][PLAYER][E] 播放失败',
      '[2026-09-05T10:00:02.000][READER][I] 阅读分页',
      '[2026-09-05T10:00:03.000][NETWORK][W] 网络慢',
    ]);
  }

  testWidgets('空日志时给出提示，复制与清空按钮禁用', (tester) async {
    await pumpPage(tester);

    expect(find.text('暂无日志'), findsOneWidget);

    final copy = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.copy_rounded),
    );
    final clear = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_outline_rounded),
    );
    expect(copy.onPressed, isNull);
    expect(clear.onPressed, isNull);
  });

  testWidgets('默认显示全部日志，频道条只列出真有日志的分类', (tester) async {
    seed();
    await pumpPage(tester);

    expect(find.text('全部 4'), findsOneWidget);
    expect(find.text('播放 2'), findsOneWidget);
    expect(find.text('阅读 1'), findsOneWidget);
    expect(find.text('网络 1'), findsOneWidget);

    // 没有日志的分类不该出现空壳按钮。
    expect(find.text('题库 0'), findsNothing);
    expect(find.byKey(const ValueKey('log_channel_QUIZ')), findsNothing);

    expect(find.textContaining('播放起播'), findsOneWidget);
    expect(find.textContaining('阅读分页'), findsOneWidget);
  });

  testWidgets('点「阅读」只留阅读日志，播放日志被过滤掉', (tester) async {
    seed();
    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('log_channel_READER')));
    await tester.pumpAndSettle();

    expect(find.textContaining('阅读分页'), findsOneWidget);
    expect(find.textContaining('播放起播'), findsNothing);
    expect(find.textContaining('网络慢'), findsNothing);
  });

  testWidgets('「仅错误」筛掉 info，留下 warn 与 error', (tester) async {
    seed();
    await pumpPage(tester);

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.filter_alt_outlined),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('播放失败'), findsOneWidget);
    expect(find.textContaining('网络慢'), findsOneWidget);
    expect(find.textContaining('播放起播'), findsNothing);
    expect(find.textContaining('阅读分页'), findsNothing);
  });

  testWidgets('筛选后无匹配时提示总行数，不假装没有日志', (tester) async {
    AppLogger.instance.lines.value = List<String>.unmodifiable([
      '[2026-09-05T10:00:00.000][PLAYER][I] 只有一条 info',
    ]);
    await pumpPage(tester);

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.filter_alt_outlined),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('共 1 行'), findsOneWidget);
    expect(find.text('暂无日志'), findsNothing);
  });

  testWidgets('复制只复制当前筛选结果，而不是全部 1000 行', (tester) async {
    seed();
    final captured = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          captured.add((call.arguments as Map)['text'] as String);
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

    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('log_channel_READER')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.copy_rounded));
    await tester.pumpAndSettle();

    expect(captured, hasLength(1));
    expect(captured.single, contains('阅读分页'));
    expect(captured.single, isNot(contains('播放起播')));
  });

  testWidgets('复制后的提示写明行数与分类范围', (tester) async {
    seed();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('log_channel_PLAYER')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.copy_rounded));
    await tester.pump();

    expect(find.text('已复制2行（播放）'), findsOneWidget);
  });

  testWidgets('日志内容可选中，方便用户长按复制单行', (tester) async {
    seed();
    await pumpPage(tester);

    expect(find.byType(SelectableText), findsWidgets);
  });
}

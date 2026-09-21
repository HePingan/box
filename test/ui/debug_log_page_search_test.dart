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

  /// 报障现场：题库同步相关日志，混着无关播放日志。
  void seedSyndrome() {
    AppLogger.instance.lines.value = List<String>.unmodifiable([
      '[2026-09-12T16:18:42.000][PLAYER][I] 播放起播',
      '[2026-09-12T16:18:44.000][QUIZ][I] sync page cursor=4900 hasMore=false',
      '[2026-09-12T16:18:45.000][QUIZ][I] sync page cursor=5000 hasMore=false',
      '[2026-09-12T16:24:09.000][QUIZ][I] sync done pages=50',
      '[2026-09-12T16:24:10.000][QUIZ][E] no candidate: bankSize=0',
      '[2026-09-12T16:25:00.000][READER][I] 阅读分页',
    ]);
  }

  Future<void> typeSearch(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('log_search_field')), text);
    await tester.pumpAndSettle();
  }

  testWidgets('日志页有搜索框（报障时能直接搜关键字）', (tester) async {
    seedSyndrome();
    await pumpPage(tester);

    expect(find.byKey(const ValueKey('log_search_field')), findsOneWidget);
  });

  testWidgets('搜关键字只留匹配行，无关频道被过滤', (tester) async {
    seedSyndrome();
    await pumpPage(tester);

    await typeSearch(tester, 'hasMore');

    expect(find.textContaining('cursor=4900'), findsOneWidget);
    expect(find.textContaining('cursor=5000'), findsOneWidget);
    // 不含 hasMore 的行必须消失
    expect(find.textContaining('播放起播'), findsNothing);
    expect(find.textContaining('阅读分页'), findsNothing);
    expect(find.textContaining('sync done'), findsNothing);
  });

  testWidgets('搜索匹配整行原文，能搜到行内任意片段（含 ID/数字）', (tester) async {
    AppLogger.instance.lines.value = List<String>.unmodifiable([
      '[2026-09-12T16:24:10.000][QUIZ][E] no candidate: bankSize=0 q_7gZgweMXMRQd',
      '[2026-09-12T16:24:11.000][QUIZ][I] sync ok',
    ]);
    await pumpPage(tester);

    await typeSearch(tester, 'q_7gZgweMXMRQd');

    expect(find.textContaining('no candidate'), findsOneWidget);
    expect(find.textContaining('sync ok'), findsNothing);
  });

  testWidgets('搜索与频道筛选叠加生效（两个条件都要满足）', (tester) async {
    seedSyndrome();
    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('log_channel_PLAYER')));
    await tester.pumpAndSettle();
    await typeSearch(tester, 'hasMore');

    // 频道=播放 且 内容含 hasMore → 一条都没有
    expect(find.textContaining('cursor=4900'), findsNothing);
    expect(find.textContaining('共 6 行'), findsOneWidget);
  });

  testWidgets('搜索与「仅错误」叠加生效', (tester) async {
    seedSyndrome();
    await pumpPage(tester);

    await typeSearch(tester, 'no candidate');
    // 注意：搜索框自身也会渲染成 EditableText，所以断言要落到日志行原文上，
    // 用 findsWidgets 会因为搜索框文本而误判。
    expect(find.textContaining('bankSize=0'), findsOneWidget);

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.filter_alt_outlined),
    );
    await tester.pumpAndSettle();

    // no candidate 是 [E]，仅错误时仍应保留
    expect(find.textContaining('bankSize=0'), findsOneWidget);
  });

  testWidgets('搜索无结果时不假装没有日志，提示说明搜索词', (tester) async {
    seedSyndrome();
    await pumpPage(tester);

    await typeSearch(tester, '不存在的关键字zzz');

    expect(find.textContaining('不存在的关键字zzz'), findsWidgets);
    expect(find.text('暂无日志'), findsNothing);
  });

  testWidgets('清空搜索恢复全部行', (tester) async {
    seedSyndrome();
    await pumpPage(tester);

    await typeSearch(tester, 'hasMore');
    expect(find.textContaining('播放起播'), findsNothing);

    await typeSearch(tester, '');
    expect(find.textContaining('播放起播'), findsOneWidget);
    expect(find.textContaining('阅读分页'), findsOneWidget);
  });

  testWidgets('复制跟随搜索：报告里写明搜索词，且不含被搜掉的行', (tester) async {
    seedSyndrome();
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
    await typeSearch(tester, 'hasMore');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.copy_rounded));
    await tester.pumpAndSettle();

    expect(captured, hasLength(1));
    expect(captured.single, contains('cursor=4900'));
    expect(captured.single, isNot(contains('播放起播')));
    // 报告头部要写明筛选条件，否则收到报告的人不知道用户搜过什么
    expect(captured.single, contains('hasMore'));
  });

  testWidgets('搜索大小写不敏感（用户不会精确敲 tag）', (tester) async {
    seedSyndrome();
    await pumpPage(tester);

    await typeSearch(tester, 'HASMORE');

    expect(find.textContaining('cursor=4900'), findsOneWidget);
  });

  testWidgets('搜索框可清空按钮，点了恢复全量', (tester) async {
    seedSyndrome();
    await pumpPage(tester);

    await typeSearch(tester, 'hasMore');
    expect(find.byKey(const ValueKey('log_search_clear')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('log_search_clear')));
    await tester.pumpAndSettle();

    expect(find.textContaining('播放起播'), findsOneWidget);
  });
}

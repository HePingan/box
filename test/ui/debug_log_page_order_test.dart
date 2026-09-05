import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/pages/debug_log_page.dart';
import 'package:box/utils/app_logger.dart';
import 'package:box/utils/diagnostic_report.dart';

/// 回归：日志页首屏必须显示**最新**的日志，而报告正文保持时间正序。
///
/// 背景：`ListView.builder` 直接按追加顺序铺 `visible`，既没有 `reverse`
/// 也没有 ScrollController。日志是 1000 行环形缓冲，用户打开「调试日志」
/// 看到的是**最旧**那批（可能是几小时前的启动日志），要报障得先手动滚到底。
/// 而报障场景恰恰是「刚出问题、马上去复制」，最新几十行才是现场。
///
/// 修法是把**展示顺序**倒过来（最新在最上面），**报告正文**仍按时间正序
/// —— 报告是给开发者读的，正序才能顺着看因果；屏幕是给用户看的，最新在前
/// 才不用滚。两者故意不同，这两条测试把这个区别锁住。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DiagnosticHeader.resetCacheForTest(
      DiagnosticHeader(
        appVersion: '9.9.9',
        buildNumber: '999',
        packageName: 'top.hpa888.box',
        osVersion: 'test',
        generatedAt: DateTime(2026, 1, 1),
      ),
    );
    await AppLogger.instance.reinitForTest();
  });

  testWidgets('首屏显示最新日志，最旧的不在第一位', (tester) async {
    for (var i = 1; i <= 40; i++) {
      AppLogger.instance.log('事件$i', tag: 'PLAYER');
    }
    // AppLogger 有 250ms 防抖落盘定时器，不清掉会触发
    // 「A Timer is still pending even after the widget tree was disposed」。
    AppLogger.instance.dispose();

    await tester.pumpWidget(const MaterialApp(home: DebugLogPage()));
    await tester.pumpAndSettle();

    // 最新一条必须在首屏可见
    expect(
      find.textContaining('事件40', findRichText: true),
      findsOneWidget,
      reason: '报障时最新的现场必须一打开就看得到，不该让用户滚 1000 行',
    );

    // 找出屏幕上最靠上的那条日志，应该是最新的而不是最旧的
    final newest = tester.getTopLeft(
      find.textContaining('事件40', findRichText: true),
    );
    final older = find.textContaining('事件39', findRichText: true);
    if (older.evaluate().isNotEmpty) {
      expect(
        newest.dy,
        lessThan(tester.getTopLeft(older).dy),
        reason: '越新的日志越靠上',
      );
    }
  });

  testWidgets('复制出的报告正文仍是时间正序', (tester) async {
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

    AppLogger.instance.log('第一条', tag: 'PLAYER');
    AppLogger.instance.log('第二条', tag: 'PLAYER');

    await tester.pumpWidget(const MaterialApp(home: DebugLogPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.copy_rounded));
    await tester.pumpAndSettle();

    expect(captured, hasLength(1));
    final body = captured.single;
    expect(
      body.indexOf('第一条'),
      lessThan(body.indexOf('第二条')),
      reason: '报告给开发者顺着读，正序才能看出因果；与屏幕的倒序展示故意不同',
    );
  });
}

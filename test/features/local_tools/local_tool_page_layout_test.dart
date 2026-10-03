// 本地工具页面的版式契约：
//   ① 内容不足一屏时卡片要**撑满**内容区（不再"半张白卡浮在上半屏"）；
//   ② 卡片里的内容要**垂直居中**，而不是全挤在顶部；
//   ③ 三个重做过的工具：没数据时说实话（`--` / 加载态），别拿 0 冒充。
import 'dart:io';

import 'package:box/features/local_tools/presentation/local_tool_panels.dart';
import 'package:box/features/local_tools/presentation/local_tools_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 典型手机：360×780 逻辑像素。
const double _w = 360;
const double _h = 780;

/// 内容区高度 = 屏高 − 顶部返回条（实测 42）。
const double _contentH = _h - 42;

Future<void> _pumpTool(WidgetTester tester, String id) async {
  tester.view.physicalSize = const Size(_w, _h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: LocalToolPage(localId: id)));
  await tester.pump(const Duration(milliseconds: 50));
}

/// 卡片「标题 + 内容」这块的实际底边：量卡片那层 Column 的**直接子节点**
/// （header / 间距 / 内容）。不能用"子树里最靠下的盒子" —— 卡片自己的内层
/// Container 比卡片矮 12px，会被算进来，量出来永远是"贴着底"。
double _cardContentBottom(WidgetTester tester, Finder card) {
  final col = find
      .descendant(of: card, matching: find.byType(Column))
      .evaluate()
      .first;
  var bottom = 0.0;
  col.visitChildren((child) {
    final ro = child.renderObject;
    if (ro is RenderBox && ro.hasSize) {
      final b = ro.localToGlobal(Offset.zero).dy + ro.size.height;
      if (b > bottom) bottom = b;
    }
  });
  return bottom;
}

void main() {
  group('卡片撑满 + 内容居中', () {
    final ids = kLocalTools.keys.toList();

    testWidgets('28 个本地工具的卡片都撑满内容区，且都不抛异常', (tester) async {
      expect(ids.length, greaterThanOrEqualTo(28));
      for (final id in ids) {
        await _pumpTool(tester, id);
        expect(tester.takeException(), isNull, reason: '「$id」构建时抛异常了');
        final card = find.byType(LocalToolCard);
        expect(card, findsOneWidget, reason: '「$id」没渲染出工具卡片');
        final rect = tester.getRect(card);
        // 卡片允许比内容区矮一点（外壳上下留白 8+24、卡片底 12），
        // 但不该再是一张"内容高度"的矮卡。
        expect(
          rect.height,
          greaterThanOrEqualTo(_contentH - 48),
          reason: '「$id」的卡片没撑满：${rect.height} / $_contentH',
        );
      }
    });

    testWidgets('内容不够高时上下留白基本对称（= 内容居中）', (tester) async {
      for (final id in ['decibel', 'compass', 'level', 'stopwatch', 'random']) {
        await _pumpTool(tester, id);
        final card = find.byType(LocalToolCard);
        final cardRect = tester.getRect(card);
        final title = find.descendant(
          of: card,
          matching: find.text(kLocalTools[id]!.title),
        );
        expect(title, findsOneWidget, reason: '「$id」卡片里找不到标题');
        final titleTop = tester.getRect(title).top;
        final bottom = _cardContentBottom(tester, card);
        final gapAbove = titleTop - cardRect.top;
        final gapBelow = cardRect.bottom - bottom;
        expect(
          (gapAbove - gapBelow).abs(),
          lessThan(40),
          reason:
              '「$id」内容不居中：上 $gapAbove / 下 $gapBelow'
              '（卡片高 ${cardRect.height}）',
        );
      }
    });
  });

  group('重做的三个工具：没数据就说实话', () {
    testWidgets('分贝仪：静止态显示 --，峰值/平均也留空，不拿 0 冒充', (tester) async {
      await _pumpTool(tester, 'decibel');
      // 大号读数 + 峰值 + 平均：三处都是 `--`，一处都不许填假数
      expect(find.text('--'), findsNWidgets(3));
      // 两个数值块
      expect(find.text('峰值'), findsOneWidget);
      expect(find.text('平均'), findsOneWidget);
      // 不该出现任何假的小数读数（0.0 / 上次的值）
      expect(find.text('0.0'), findsNothing);
      // 色带与参考表
      expect(find.text('常见噪音参考'), findsOneWidget);
      expect(find.text('树叶沙沙'), findsOneWidget);
      expect(find.text('正常交谈'), findsOneWidget);
      expect(find.text('电钻'), findsOneWidget);
      expect(find.text('测了就能对上'), findsOneWidget);
      // 量程刻度
      for (final v in ['30', '60', '90', '120']) {
        expect(find.text(v), findsOneWidget, reason: '色带缺刻度 $v');
      }
    });

    testWidgets('分贝仪参考表的进度槽有实际宽度（不准被算成 0 宽）', (tester) async {
      await _pumpTool(tester, 'decibel');
      // 每行 = 「名字 + 槽 + 数值」。槽是 Row 里的 ClipRRect。
      final slot = find
          .descendant(
            of: find
                .ancestor(of: find.text('树叶沙沙'), matching: find.byType(Row))
                .first,
            matching: find.byType(ClipRRect),
          )
          .first;
      final rect = tester.getRect(slot);
      expect(rect.height, 6);
      expect(rect.width, greaterThan(60), reason: '进度槽宽度塌了：${rect.width}');
    });

    test('分贝仪给 record 的是真实临时路径（空串会让安卓侧原生崩溃）', () {
      // 场景：真机上点「开始测量」直接闪退。record 7.x 的 `start()` 签名是
      // `{required String path}`；传空串会一路走到
      // `MediaRecorder.setOutputFile("")` —— 原生崩溃，Dart 侧 catch 不住。
      // 这条护栏钉住：不许再出现空路径，且必须走临时目录 + 停时删掉。
      final src = File(
        'lib/features/local_tools/presentation/local_tool_panels.dart',
      ).readAsStringSync();
      final start = src.indexOf('class _DecibelPanelBodyState');
      expect(start, greaterThan(0), reason: '找不到分贝仪的实现');
      // 先把 // 与 /// 的注释行去掉再查 —— 注释里讲这件事是正常的，
      // 但源码护栏会被自己的注释骗到（本仓踩过好几次）。
      final body = src
          .substring(start)
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        body.contains("path: ''"),
        isFalse,
        reason: '又给 record 传空路径了 —— 真机上会闪退',
      );
      expect(
        body.contains('getTemporaryDirectory()'),
        isTrue,
        reason: '要录到临时目录里的真实文件',
      );
      expect(
        body.contains('_removeTempFile()'),
        isTrue,
        reason: '停止/退出时要删掉录音临时文件',
      );
    });

    testWidgets('分贝仪按钮：开始可点、停止在没开始时不可点', (tester) async {
      await _pumpTool(tester, 'decibel');
      final start = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '开始测量'),
      );
      final stop = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '停止'),
      );
      expect(start.onPressed, isNotNull);
      expect(stop.onPressed, isNull);
    });

    testWidgets('指南针：拿不到磁力计时是加载态，不显示方位读数', (tester) async {
      await _pumpTool(tester, 'compass');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // 盘面没出来，就不该有「北」这种方位字样
      expect(find.text('北'), findsNothing);
      expect(find.textContaining('°  '), findsNothing);
    });

    testWidgets('水平仪：拿不到加速度计时是加载态，不显示 0.0° 冒充水平', (tester) async {
      await _pumpTool(tester, 'level');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('0.0°'), findsNothing);
      expect(find.text('前后倾'), findsNothing);
    });
  });
}

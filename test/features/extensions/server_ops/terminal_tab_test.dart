// 服务器运维插件：「终端」页签的用例。
//
// 这里**不真的建 WebViewController**：widget 测试里没有平台实现，建了就会抛。
// 需要被验证的是"凭据怎么算"与"没口令时的引导"这两件事——
// 它们决定用户会不会看到 401 白屏，且都能在不碰平台的情况下测到。
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:box/features/extensions/plugins/server_ops/terminal_controls.dart';
import 'package:box/features/extensions/plugins/server_ops/terminal_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Basic 凭据', () {
    test('没口令时不给凭据（页面改走"先去设置里填"）', () {
      expect(opsTerminalCredential(const ServerOpsSettings()), isNull);
      expect(
        opsTerminalCredential(const ServerOpsSettings(password: '   ')),
        isNull,
      );
    });

    test('有口令时给出用户名 + 口令（用户名缺省是 boxops）', () {
      final credential = opsTerminalCredential(
        const ServerOpsSettings(password: 'pw'),
      );
      expect(credential, isNotNull);
      expect(credential!.user, 'boxops');
      expect(credential.password, 'pw');
    });

    test('用户填过的用户名以其为准', () {
      final credential = opsTerminalCredential(
        const ServerOpsSettings(user: 'someone', password: 'pw'),
      );
      expect(credential!.user, 'someone');
    });
  });

  group('没有口令时的引导', () {
    testWidgets('给出说明与「去设置」入口，点它回调出去', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ServerOpsTerminalTab(
              settings: const ServerOpsSettings(),
              onOpenSettings: () => opened += 1,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('还没配置终端口令'), findsOneWidget);
      expect(find.textContaining('构建注入过就不用填'), findsOneWidget);

      await tester.tap(find.text('去设置'));
      await tester.pump();
      expect(opened, 1);
    });
  });

  group('辅助键栏（A6）', () {
    /// 把栏子单独挂起来测：它不需要 WebView，所以"点哪个键回调哪个键"是真能验的。
    Future<({List<TerminalAuxKey> keys, List<String> combos, List<int> paste, List<int> ctrlToggle})>
        pumpBar(WidgetTester tester, {bool ctrlArmed = false}) async {
      // 计数用 List 而不是 int：record 里的 int 是值拷贝，回调改了外面也看不见，
      // 会得到"明明点了却是 0"的假失败。
      final keys = <TerminalAuxKey>[];
      final combos = <String>[];
      final paste = <int>[];
      final ctrlToggle = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalAuxBar(
              ctrlArmed: ctrlArmed,
              onToggleCtrl: () => ctrlToggle.add(1),
              onKey: keys.add,
              onPaste: () => paste.add(1),
              onCtrlCombo: combos.add,
            ),
          ),
        ),
      );
      await tester.pump();
      return (keys: keys, combos: combos, paste: paste, ctrlToggle: ctrlToggle);
    }

    testWidgets('六个辅助键都在，点 Tab / 方向键回调对应的键', (tester) async {
      final r = await pumpBar(tester);
      for (final label in <String>['Ctrl', 'Tab', '↑', '↓', '←', '→', '粘贴']) {
        expect(find.text(label), findsOneWidget, reason: '缺了 $label');
      }

      await tester.tap(find.text('Tab'));
      await tester.pump();
      await tester.tap(find.text('↑'));
      await tester.pump();
      await tester.tap(find.text('←'));
      await tester.pump();

      expect(r.keys, <TerminalAuxKey>[
        TerminalAuxKey.tab,
        TerminalAuxKey.arrowUp,
        TerminalAuxKey.arrowLeft,
      ]);
    });

    testWidgets('点 Ctrl 只切状态（回调出去），不当成按了一次 Tab', (tester) async {
      final r = await pumpBar(tester);
      await tester.tap(find.text('Ctrl'));
      await tester.pump();
      expect(r.ctrlToggle, hasLength(1));
      expect(r.keys, isEmpty);
    });

    testWidgets('Ctrl 待命时按钮点亮（换成实心），否则是描边', (tester) async {
      await pumpBar(tester);
      expect(find.byType(FilledButton), findsNothing);
      await pumpBar(tester, ctrlArmed: true);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('粘贴按钮回调出去（真正取剪贴板由页面做）', (tester) async {
      final r = await pumpBar(tester);
      await tester.tap(find.text('粘贴'));
      await tester.pump();
      expect(r.paste, hasLength(1));
      expect(r.keys, isEmpty);
    });

    testWidgets('长按 Ctrl 弹出组合键清单，选一条回调字母', (tester) async {
      final r = await pumpBar(tester);
      await tester.longPress(find.text('Ctrl'));
      await tester.pumpAndSettle();

      expect(find.text('Ctrl 组合键'), findsOneWidget);
      expect(find.text('Ctrl+C 中断当前命令'), findsOneWidget);
      await tester.tap(find.text('Ctrl+C 中断当前命令'));
      await tester.pumpAndSettle();
      expect(r.combos, <String>['c']);
    });
  });
}

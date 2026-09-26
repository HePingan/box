// 服务器运维插件：「终端」页签的用例。
//
// 这里**不真的建 WebViewController**：widget 测试里没有平台实现，建了就会抛。
// 需要被验证的是"凭据怎么算"与"没口令时的引导"这两件事——
// 它们决定用户会不会看到 401 白屏，且都能在不碰平台的情况下测到。
import 'package:box/features/extensions/plugins/server_ops/server_ops_runtime.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:box/features/extensions/plugins/server_ops/terminal_controls.dart';
import 'package:box/features/extensions/plugins/server_ops/terminal_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 单台服务器的等价构造：口令只在内存缓存里（对应"从加密存储读出来"那一刻）。
const _oneServer = ServerOpsServer(id: 's1', label: '测试机');

ServerOpsSettings _withPassword(String password, {String user = ''}) =>
    ServerOpsSettings(
      servers: [_oneServer.copyWith(user: user)],
      selectedServerId: 's1',
      passwords: {'s1': password},
    );

void main() {
  group('换过凭据要先清 WebView 的凭据缓存（296）', () {
    // 真机现场：在设置里把口令换成设备凭据之后，终端页的 /term/ws 带的还是旧用户名 ——
    // Android WebView 按 (源 + realm) 缓存 Basic 凭据，缓存命中时 onHttpAuthRequest
    // 不会被调用，App 也就没机会给新凭据。所以进页面时凭据变了就先清一次缓存。
    test('凭据指纹：没口令是空串，换了用户名或口令都算变', () {
      expect(opsTerminalAuthFingerprint(null), isEmpty);
      const a = WebViewCredential(user: 'u1', password: 'p1');
      const b = WebViewCredential(user: 'u1', password: 'p2');
      const c = WebViewCredential(user: 'u2', password: 'p1');
      expect(opsTerminalAuthFingerprint(a), isNot(opsTerminalAuthFingerprint(b)));
      expect(opsTerminalAuthFingerprint(a), isNot(opsTerminalAuthFingerprint(c)));
      expect(
        opsTerminalAuthFingerprint(const WebViewCredential(user: 'u1', password: 'p1')),
        opsTerminalAuthFingerprint(a),
      );
    });

    test('该不该清：第一次进要清；同一份凭据再进不清', () {
      const cred = WebViewCredential(user: 'phone-hpa888', password: 'pw');
      expect(
        opsTerminalNeedsCredentialCacheClear(credential: cred, previousFingerprint: ''),
        isTrue,
      );
      expect(
        opsTerminalNeedsCredentialCacheClear(
          credential: cred,
          previousFingerprint: opsTerminalAuthFingerprint(cred),
        ),
        isFalse,
      );
      expect(
        opsTerminalNeedsCredentialCacheClear(
          credential: const WebViewCredential(user: 'boxops', password: 'old'),
          previousFingerprint: opsTerminalAuthFingerprint(cred),
        ),
        isTrue,
        reason: '换回旧凭据同样是"变了"，也得清一次',
      );
    });

    test('平台侧没有这条通道也不抛（单测 / 非 Android / 老安装）', () async {
      debugSetServerOpsRuntime();
      await serverOpsClearWebViewAuthCache();
    });

    test('接缝可注入：页面调的确实是注入进去的那份', () async {
      var calls = 0;
      debugSetServerOpsRuntime(webViewAuthCacheClearer: () async => calls++);
      await serverOpsClearWebViewAuthCache();
      await serverOpsClearWebViewAuthCache();
      expect(calls, 2);
      debugSetServerOpsRuntime();
    });
  });

  group('Basic 凭据', () {
    test('没口令时不给凭据（页面改走"先去设置里填"）', () {
      expect(opsTerminalCredential(const ServerOpsSettings()), isNull);
      expect(
        opsTerminalCredential(_withPassword('   ')),
        isNull,
        reason: '全是空白的口令等于没配',
      );
    });

    test('内置主服务端：用户名缺省就是构建默认（boxops）', () {
      final credential = opsTerminalCredential(
        const ServerOpsSettings(
          servers: [ServerOpsServer(id: 'hpa888', label: '主服务端')],
          selectedServerId: 'hpa888',
          passwords: {'hpa888': 'pw'},
        ),
      );
      expect(credential, isNotNull);
      expect(credential!.user, ServerOpsSettings.defaultUser);
      expect(credential.password, 'pw');
    });

    test('用户自己加的机器：用户名没填就不给凭据（走“先去设置里填”，不是拿空用户名去 401）', () {
      // 真机坑：用户名空着时 Basic 只会拿回 401，而文案说“口令不对”，方向就查偏了。
      expect(
        opsTerminalCredential(_withPassword('pw')),
        isNull,
        reason: 'id 不在内置名单里、又没填用户名 → 不该默默用 boxops',
      );
      expect(
        opsTerminalCredential(_withPassword('pw', user: 'phone-x')),
        isNotNull,
      );
    });

    test('用户填过的用户名以其为准', () {
      final credential = opsTerminalCredential(
        _withPassword('pw', user: 'someone'),
      );
      expect(credential!.user, 'someone');
    });

    test('凭据按当前选中的那台算（切了机器就换人）', () {
      const onA = ServerOpsSettings(
        servers: [
          ServerOpsServer(id: 'a', label: 'A 机', user: 'ua'),
          ServerOpsServer(id: 'b', label: 'B 机', user: 'ub'),
        ],
        selectedServerId: 'a',
        passwords: {'a': 'pw-a', 'b': 'pw-b'},
      );
      const onB = ServerOpsSettings(
        servers: [
          ServerOpsServer(id: 'a', label: 'A 机', user: 'ua'),
          ServerOpsServer(id: 'b', label: 'B 机', user: 'ub'),
        ],
        selectedServerId: 'b',
        passwords: {'a': 'pw-a', 'b': 'pw-b'},
      );
      expect(opsTerminalCredential(onA)!.user, 'ua');
      expect(opsTerminalCredential(onA)!.password, 'pw-a');
      expect(opsTerminalCredential(onB)!.user, 'ub');
      expect(opsTerminalCredential(onB)!.password, 'pw-b');
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

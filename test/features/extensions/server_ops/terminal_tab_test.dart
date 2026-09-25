// 服务器运维插件：「终端」页签的用例。
//
// 这里**不真的建 WebViewController**：widget 测试里没有平台实现，建了就会抛。
// 需要被验证的是"凭据怎么算"与"没口令时的引导"这两件事——
// 它们决定用户会不会看到 401 白屏，且都能在不碰平台的情况下测到。
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
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
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/update/update_dialog.dart';
import 'package:box/update/update_models.dart';

UpdateManifest _manifest() => UpdateManifest.fromJson(<String, dynamic>{
  'appId': 'box',
  'platform': 'android',
  'channel': 'release',
  'packageName': 'top.hpa888.box',
  'latestVersionCode': 200,
  'latestVersionName': '2.0.0',
  'forceUpdate': true,
  'minSupportedVersionCode': 200,
  'downloadUrl': 'https://box.hpa888.top/updates/box/android/release/a.apk',
  'sha256': 'a' * 64,
  'fileSize': 1024,
  'changelog': <String>['测试'],
});

Future<void> _pump(WidgetTester tester, {required bool force}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: UpdateDialog(
          manifest: _manifest(),
          currentVersionName: '1.6.9',
          currentVersionCode: 169,
          force: force,
          installOverride: () async {
            throw Exception('系统拒绝安装: INSTALL_FAILED_UPDATE_INCOMPATIBLE');
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('强更时初始不可退出（保持原行为）', (tester) async {
    await _pump(tester, force: true);
    expect(find.text('更新'), findsOneWidget);
    expect(find.text('退出应用'), findsNothing);
    expect(find.textContaining('卸载'), findsNothing);
  });

  testWidgets('遇到不可恢复的安装失败后，强更弹窗必须给出逃生门', (tester) async {
    await _pump(tester, force: true);

    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();

    // 关键断言：用户不能被永久锁死。
    expect(
      find.textContaining('卸载'),
      findsWidgets,
      reason: '签名不一致时必须告诉用户需要卸载重装',
    );
    expect(
      find.text('导出备份'),
      findsOneWidget,
      reason: '劝用户卸载之前必须先给备份入口，否则等于让他丢数据',
    );
    expect(
      find.text('复制下载链接'),
      findsOneWidget,
      reason: '要给手动下载路径，不能只剩一个装不上的更新按钮',
    );

    // 不可恢复时「更新」按钮应当撤掉，避免用户无意义地反复点。
    expect(find.text('更新'), findsNothing);
  });

  testWidgets('可重试的失败不应触发逃生门，也不该劝用户卸载', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateDialog(
            manifest: _manifest(),
            currentVersionName: '1.6.9',
            currentVersionCode: 169,
            force: true,
            installOverride: () async {
              throw Exception('Connection closed');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();

    expect(find.textContaining('卸载'), findsNothing);
    expect(find.text('更新'), findsOneWidget, reason: '网络失败要允许用户再试一次');
  });
}

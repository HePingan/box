import 'package:box/update/update_dialog.dart';
import 'package:box/update/update_models.dart';
import 'package:box/update/update_security.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A3 回归：UpdateDialog 必须把 security 配置往下传给安装器。
///
/// 之前 dialog 根本没有这个参数，安装器只能用默认的空白名单（等于全放通）。
void main() {
  UpdateManifest manifest() => UpdateManifest.fromJson(<String, dynamic>{
    'appId': 'box',
    'platform': 'android',
    'channel': 'release',
    'packageName': 'top.hpa888.box',
    'latestVersionCode': 200,
    'latestVersionName': '2.0.0',
    'downloadUrl': 'https://box.hpa888.top/a.apk',
    'sha256': 'a' * 64,
    'changelog': <String>['修复若干问题'],
  });

  testWidgets('security 参数存在且被保留', (tester) async {
    const security = UpdateManifestSecurityConfig(
      allowedDownloadHosts: {'box.hpa888.top'},
    );

    final widget = UpdateDialog(
      manifest: manifest(),
      currentVersionName: '1.6.9',
      currentVersionCode: 169,
      force: false,
      security: security,
    );

    expect(widget.security.allowedDownloadHosts, contains('box.hpa888.top'));

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
    await tester.pumpAndSettle();

    // 关键信息要真的渲染出来，避免只改了参数没接上 UI。
    expect(find.textContaining('2.0.0'), findsWidgets);
    expect(find.textContaining('1.6.9'), findsWidgets);
    expect(find.text('更新'), findsOneWidget);
  });

  testWidgets('未传 security 时有安全的默认值', (tester) async {
    final widget = UpdateDialog(
      manifest: manifest(),
      currentVersionName: '1.6.9',
      currentVersionCode: 169,
      force: false,
    );
    // 默认要求 https，这条不能因为加了参数而退化。
    expect(widget.security.requireHttpsDownloadUrl, isTrue);
  });
}

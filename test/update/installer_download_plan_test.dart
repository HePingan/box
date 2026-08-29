import 'package:box/update/update_download_plan.dart';
import 'package:box/update/update_models.dart';
import 'package:box/update/update_security.dart';
import 'package:flutter_test/flutter_test.dart';

/// A2 + A3 回归：备用下载地址必须真被使用，且下载前要过域名白名单。
///
/// A2 真实现象：后台 manifest 有 `backupDownloadUrl` 字段、模型也解析了，
/// 但 grep 整个 lib/ 只有模型层出现——下载逻辑从来没读过它。主地址挂了
/// 就直接失败，备用线路形同虚设。
///
/// A3 真实现象：`app_installer_io.dart:21` 调 validateUpdateDownloadUrl 时
/// 没传 allowedHosts，而空白名单在 update_security.dart 里等于全放通。
/// 验签层已拦住，所以这条是纵深防御补一层，不是已发生的漏洞。
UpdateManifest manifestWith({
  required String downloadUrl,
  String? backupDownloadUrl,
}) {
  return UpdateManifest.fromJson(<String, dynamic>{
    'schemaVersion': 1,
    'appId': 'box',
    'platform': 'android',
    'channel': 'release',
    'packageName': 'com.example.box',
    'latestVersionCode': 170,
    'latestVersionName': '1.7.0',
    'minSupportedVersionCode': 0,
    'blockedVersionCodes': <int>[],
    'forceUpdate': false,
    'title': 'Box 1.7.0',
    'notice': '',
    'changelog': <String>[],
    'downloadUrl': downloadUrl,
    'backupDownloadUrl': backupDownloadUrl,
    'sha256': 'a' * 64,
    'fileSize': 59992363,
    'publishedAt': '2026-08-29T00:00:00+00:00',
    'supportUrl': '',
  });
}

void main() {
  const security = UpdateManifestSecurityConfig(
    signatureMode: UpdateManifestSignatureMode.hmacSha256,
    hmacSecret: 'irrelevant-for-url-planning',
    allowedDownloadHosts: {'box.hpa888.top'},
  );

  group('A2 备用地址进入下载计划', () {
    test('主地址与备用地址都在计划里，主地址在前', () {
      final plan = buildUpdateDownloadPlan(
        manifest: manifestWith(
          downloadUrl: 'https://box.hpa888.top/updates/a.apk',
          backupDownloadUrl: 'https://box.hpa888.top/mirror/a.apk',
        ),
        security: security,
      );

      expect(plan, <String>[
        'https://box.hpa888.top/updates/a.apk',
        'https://box.hpa888.top/mirror/a.apk',
      ]);
    });

    test('备用地址为空时只有主地址', () {
      for (final backup in <String?>[null, '', '   ']) {
        final plan = buildUpdateDownloadPlan(
          manifest: manifestWith(
            downloadUrl: 'https://box.hpa888.top/updates/a.apk',
            backupDownloadUrl: backup,
          ),
          security: security,
        );
        expect(plan, hasLength(1), reason: 'backup=${backup?.length}');
      }
    });

    test('备用地址与主地址相同时不重复尝试', () {
      const url = 'https://box.hpa888.top/updates/a.apk';
      final plan = buildUpdateDownloadPlan(
        manifest: manifestWith(downloadUrl: url, backupDownloadUrl: url),
        security: security,
      );
      expect(plan, <String>[url]);
    });
  });

  group('A3 白名单在下载计划阶段生效', () {
    test('白名单外的备用地址被剔除，但主地址仍可用', () {
      final plan = buildUpdateDownloadPlan(
        manifest: manifestWith(
          downloadUrl: 'https://box.hpa888.top/updates/a.apk',
          backupDownloadUrl: 'https://evil.example.com/a.apk',
        ),
        security: security,
      );

      expect(plan, <String>['https://box.hpa888.top/updates/a.apk']);
    });

    test('主地址不在白名单内时直接抛异常', () {
      expect(
        () => buildUpdateDownloadPlan(
          manifest: manifestWith(
            downloadUrl: 'https://evil.example.com/a.apk',
          ),
          security: security,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('http 明文地址被拒绝', () {
      expect(
        () => buildUpdateDownloadPlan(
          manifest: manifestWith(
            downloadUrl: 'http://box.hpa888.top/updates/a.apk',
          ),
          security: security,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('子域名按后缀规则放通', () {
      final plan = buildUpdateDownloadPlan(
        manifest: manifestWith(
          downloadUrl: 'https://cdn.box.hpa888.top/updates/a.apk',
        ),
        security: security,
      );
      expect(plan, hasLength(1));
    });

    test('空地址抛异常', () {
      expect(
        () => buildUpdateDownloadPlan(
          manifest: manifestWith(downloadUrl: ''),
          security: security,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}

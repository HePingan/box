@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:box/update/update_models.dart';
import 'package:box/update/update_security.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真联网联调：拿线上后台的真实响应，用真实密钥验签。
///
/// 默认不随全量测试跑（需要外网 + 本机密钥文件）：
///   flutter test --tags live test/update/update_live_backend_test.dart
///
/// 这条用例覆盖单测覆盖不到的东西：服务端真实的 canonical JSON 口径
/// （中文不转义、键排序、无空格分隔符）与客户端是否逐字节一致。
void main() {
  const checkUrl = 'https://box.hpa888.top/api/v1/app-updates/check';
  const secretFile = '/root/.secrets/box-update-manifest-sign-secret';

  late String secret;

  setUpAll(() {
    final f = File(secretFile);
    if (!f.existsSync()) {
      fail('缺少密钥文件 $secretFile，无法做真验签');
    }
    secret = f.readAsStringSync().trim();
  });

  Future<Map<String, dynamic>> fetchCheck(int versionCode) async {
    final uri = Uri.parse(checkUrl).replace(
      queryParameters: <String, String>{
        'app_id': 'box',
        'platform': 'android',
        'channel': 'release',
        'version_code': '$versionCode',
        'package_name': 'com.example.box',
      },
    );

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'box-update-live-test');
      final res = await req.close();
      expect(res.statusCode, 200, reason: 'check 接口应返回 200');
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return (decoded['data'] as Map).cast<String, dynamic>();
    } finally {
      client.close(force: true);
    }
  }

  test('线上 check 响应能用真实密钥验签通过', () async {
    final data = await fetchCheck(169);

    expect(
      data['signatureAlgorithm'],
      'HMAC-SHA256',
      reason: '服务端启用了 HMAC 签名',
    );

    final security = UpdateManifestSecurityConfig(
      signatureMode: UpdateManifestSignatureMode.hmacSha256,
      hmacSecret: secret,
      allowedDownloadHosts: const {'box.hpa888.top'},
    );

    final result = verifyUpdateManifestSignature(
      manifestJson: data,
      security: security,
    );

    expect(
      result.passed,
      isTrue,
      reason: '真实响应验签失败：${result.message}\n'
          'expected=${result.expected}\nactual=${result.actual}',
    );
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('线上响应能通过完整安全校验（含下载域名与 sha256）', () async {
    final data = await fetchCheck(169);
    final manifest = UpdateManifest.fromJson(data);

    final security = UpdateManifestSecurityConfig(
      signatureMode: UpdateManifestSignatureMode.hmacSha256,
      hmacSecret: secret,
      allowedDownloadHosts: const {'box.hpa888.top'},
    );

    // 这是客户端 checkUpdate 里实际调用的那一条，任何一项不合格都会抛异常。
    expect(
      () => validateUpdateManifestSecurity(
        manifest: manifest,
        rawManifestJson: data,
        security: security,
      ),
      returnsNormally,
    );
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('后台发布的版本号与当前工程版本的关系是可解释的', () async {
    final data = await fetchCheck(169);
    final latest = data['latestVersionCode'] as int;

    // 不断言「后台一定比本地新」——那取决于运营是否发布了新版。
    // 只断言服务端的运行时结论与版本号事实自洽，防止出现
    // 「已是最新版却被强制更新」这类历史 bug 回归。
    final hasNew = data['hasNewVersion'] as bool;
    expect(
      hasNew,
      latest > 169,
      reason: 'hasNewVersion 应等于 latestVersionCode > currentVersionCode',
    );

    if (!hasNew) {
      expect(
        data['effectiveForceUpdate'],
        isFalse,
        reason: '没有新版本时不得强制更新（历史 bug：已是最新仍被强更）',
      );
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}

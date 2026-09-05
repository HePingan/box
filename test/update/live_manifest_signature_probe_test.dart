@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:box/update/update_security.dart';

/// 拿**线上真实 manifest** + 真实密钥，跑客户端自己的验签代码。
///
/// 为什么需要它：单测里造的 manifest 永远能自证通过（自己签自己验），
/// 挡不住「服务端签名口径与客户端不一致」这类问题。1.9.8 发出去才发现
/// 更新链路是断的，就是因为从没在真实数据上验过一次。
///
/// 需要密钥，默认跳过。跑法：
///   SECRET=$(cat /root/.secrets/box-update-manifest-sign-secret) \
///   flutter test test/update/live_manifest_signature_probe_test.dart \
///     --dart-define=UPDATE_SIGNATURE_SECRET="$SECRET" --tags live
void main() {
  const secret = String.fromEnvironment('UPDATE_SIGNATURE_SECRET');

  test('线上 manifest 能通过客户端验签', () async {
    if (secret.isEmpty) {
      markTestSkipped('未注入 UPDATE_SIGNATURE_SECRET，跳过线上验签探针');
      return;
    }

    final client = HttpClient();
    late Map<String, dynamic> manifest;
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://box.hpa888.top/updates/box/android/release/version.json',
        ),
      );
      final resp = await req.close();
      expect(resp.statusCode, 200, reason: '取不到线上 version.json');
      final body = await resp.transform(utf8.decoder).join();
      manifest = jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }

    // 先确认服务端确实签了名，否则这条探针等于没验。
    expect(
      manifest['signature'],
      isA<String>(),
      reason: 'manifest 里没有 signature 字段，服务端没签名',
    );
    expect(manifest['signatureAlgorithm'], 'HMAC-SHA256');

    final result = verifyUpdateManifestSignature(
      manifestJson: manifest,
      security: const UpdateManifestSecurityConfig(
        signatureMode: UpdateManifestSignatureMode.hmacSha256,
        hmacSecret: secret,
        requireSha256: true,
        allowedDownloadHosts: <String>{'box.hpa888.top'},
      ),
    );

    expect(
      result.passed,
      isTrue,
      reason:
          '线上 manifest 验签失败：${result.message}\n'
          'expected=${result.expected}\nactual=${result.actual}',
    );
  });
}

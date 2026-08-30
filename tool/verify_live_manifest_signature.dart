// 用真实 secret 对线上 check 接口返回的清单做验签，复现/确认客户端行为。
//
// 为什么需要它：1.7.3 事故是「包里没有 secret」，靠肉眼看构建命令发现不了。
// 这个脚本走客户端同一套 canonical/HMAC 代码，对真实线上响应验签，能直接回答
// 「装上这个包后检查更新会不会报签名错」。
//
// 用法：
//   dart run tool/verify_live_manifest_signature.dart <versionCode>
// secret 从 /root/.secrets/box-update-manifest-sign-secret 读取，不回显。
import 'dart:convert';
import 'dart:io';

import 'package:box/update/update_security.dart';

Future<void> main(List<String> args) async {
  final versionCode = args.isNotEmpty ? args.first : '172';
  final secretFile = File('/root/.secrets/box-update-manifest-sign-secret');
  if (!secretFile.existsSync()) {
    stderr.writeln('缺少 secret 文件: ${secretFile.path}');
    exit(1);
  }
  final secret = secretFile.readAsStringSync().replaceAll(RegExp(r'[\r\n]'), '');

  final uri = Uri.parse(
    'https://box.hpa888.top/api/v1/app-updates/check'
    '?app_id=box&platform=android&package_name=top.hpa888.box'
    '&version_code=$versionCode',
  );

  final client = HttpClient();
  final req = await client.getUrl(uri);
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  client.close();

  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final manifest = (decoded['data'] as Map).cast<String, dynamic>();

  stdout.writeln('线上清单: ${manifest['latestVersionName']} '
      '(${manifest['latestVersionCode']}) algo=${manifest['signatureAlgorithm']}');

  final result = verifyUpdateManifestSignature(
    manifestJson: manifest,
    security: UpdateManifestSecurityConfig(
      signatureMode: UpdateManifestSignatureMode.hmacSha256,
      hmacSecret: secret,
      requireSha256: true,
      allowedDownloadHosts: const <String>{'box.hpa888.top'},
    ),
  );

  stdout.writeln('验签结果: passed=${result.passed} message=${result.message}');
  if (!result.passed) {
    stdout.writeln('  expected(前16): ${result.expected.substring(0, 16)}');
    stdout.writeln('  actual  (前16): ${result.actual.substring(0, 16)}');
    exit(1);
  }
}

import 'dart:convert';

import 'package:box/update/update_security.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归用例：check API 在**签名之后**追加运行时字段，客户端验签必须先剥离它们。
///
/// 真实现象（实测 https://box.hpa888.top/api/v1/app-updates/check）：
/// 服务端 `build_manifest()` 只对发布字段算 HMAC，随后 check 接口把
/// `hasNewVersion` / `currentVersionCode` 等 6 个运行时字段塞进同一个 JSON。
/// 客户端若对收到的整个 map 算 HMAC，必然算出不同的值 → 「更新清单签名不匹配」。
///
/// 服务端签名口径（app/services.py:126-139）：
///   json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
///   HMAC-SHA256(secret, canonical).hexdigest()
void main() {
  const secret = 'test-manifest-sign-secret-0123456789';

  /// 服务端 build_manifest() 产出的、参与签名的发布字段。
  Map<String, dynamic> publishedFields() => <String, dynamic>{
    'schemaVersion': 1,
    'appId': 'box',
    'platform': 'android',
    'channel': 'release',
    'packageName': 'top.hpa888.box',
    'latestVersionCode': 118,
    'latestVersionName': '1.1.8',
    'minSupportedVersionCode': 0,
    'blockedVersionCodes': <int>[],
    'forceUpdate': true,
    'title': 'Box 1.1.8',
    'notice': '建议升级到最新版本以获得稳定性与功能改进。',
    'changelog': <String>['远程更新链路加固', '修复已是最新版本仍被强制更新的问题'],
    'downloadUrl':
        'https://box.hpa888.top/updates/box/android/release/box-1.1.8-118.apk',
    'backupDownloadUrl': '',
    'sha256':
        '20bc2ca602c6c174e09d83580b330a2bd68f86c1af30f1753683b0211fc7decb',
    'fileSize': 59992363,
    'publishedAt': '2026-07-21T13:34:18.101436+00:00',
    'supportUrl': '',
  };

  /// 用与服务端完全一致的口径签名。
  String signLikeServer(Map<String, dynamic> published) {
    final canonical = updateManifestCanonicalJson(published);
    return Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode(canonical)).toString();
  }

  /// check 接口的真实响应：已签名字段 + 签名 + 事后追加的运行时字段。
  Map<String, dynamic> checkApiResponse({int currentVersionCode = 169}) {
    final published = publishedFields();
    return <String, dynamic>{
      ...published,
      'signatureAlgorithm': 'HMAC-SHA256',
      'signature': signLikeServer(published),
      // ↓ 服务端在签名之后追加，不参与 HMAC
      'currentVersionCode': currentVersionCode,
      'hasNewVersion': false,
      'updateRequired': false,
      'effectiveForceUpdate': false,
      'deviceId': null,
      'userId': null,
    };
  }

  const security = UpdateManifestSecurityConfig(
    signatureMode: UpdateManifestSignatureMode.hmacSha256,
    hmacSecret: secret,
    allowedDownloadHosts: {'box.hpa888.top'},
  );

  test('剥离运行时字段后，真实 check 响应能验签通过', () {
    final result = verifyUpdateManifestSignature(
      manifestJson: checkApiResponse(),
      security: security,
    );

    expect(
      result.passed,
      isTrue,
      reason: '服务端只对发布字段签名，客户端必须先剥离运行时字段：${result.message}',
    );
  });

  test('运行时字段的值变化不影响验签结果', () {
    // 同一个发布版本，面对不同客户端版本号会返回不同的运行时结论，
    // 但签名是发布时算好的，不能因此失效。
    for (final code in <int>[1, 117, 118, 169, 999]) {
      final result = verifyUpdateManifestSignature(
        manifestJson: checkApiResponse(currentVersionCode: code),
        security: security,
      );
      expect(
        result.passed,
        isTrue,
        reason: 'currentVersionCode=$code 时验签失败：${result.message}',
      );
    }
  });

  test('篡改已签名字段仍然会被拒绝', () {
    final tampered = checkApiResponse();
    tampered['downloadUrl'] = 'https://box.hpa888.top/updates/evil.apk';

    final result = verifyUpdateManifestSignature(
      manifestJson: tampered,
      security: security,
    );

    expect(result.passed, isFalse, reason: '换掉下载地址必须验签失败');
  });

  test('篡改 latestVersionCode 会被拒绝', () {
    final tampered = checkApiResponse();
    tampered['latestVersionCode'] = 99999;

    final result = verifyUpdateManifestSignature(
      manifestJson: tampered,
      security: security,
    );

    expect(result.passed, isFalse, reason: '拉高版本号强推更新必须验签失败');
  });

  test('伪造运行时字段不能绕过签名校验', () {
    // 攻击者把运行时字段塞进签名正文来试图影响结果：
    // 剥离逻辑必须按固定白名单剥离，而不是「谁不在签名里就剥掉」。
    final tampered = checkApiResponse();
    tampered['hasNewVersion'] = true;
    tampered['effectiveForceUpdate'] = true;

    final result = verifyUpdateManifestSignature(
      manifestJson: tampered,
      security: security,
    );

    // 运行时字段本就不参与签名，改它们不影响验签通过；
    // 真正的防线是 needForceUpdate() 只信已签名字段 + 本地版本号比较。
    expect(result.passed, isTrue);
  });

  test('signaturePayload 会剥离全部 6 个运行时字段', () {
    final payload = updateManifestSignaturePayload(checkApiResponse());

    for (final key in const [
      'currentVersionCode',
      'hasNewVersion',
      'updateRequired',
      'effectiveForceUpdate',
      'deviceId',
      'userId',
      'signature',
      'signatureAlgorithm',
    ]) {
      expect(payload.containsKey(key), isFalse, reason: '$key 应被剥离');
    }

    // 已签名字段必须一个都不少，否则会算出不同的 canonical。
    expect(payload.keys.toSet(), publishedFields().keys.toSet());
  });
}

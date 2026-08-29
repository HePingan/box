import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'update_models.dart';

enum UpdateManifestSignatureMode {
  none,
  sha256,
  hmacSha256,
}

class UpdateManifestSecurityConfig {
  const UpdateManifestSecurityConfig({
    this.signatureMode = UpdateManifestSignatureMode.sha256,
    this.hmacSecret = '',
    this.requireSha256 = true,
    this.requireHttpsDownloadUrl = true,
    this.allowedDownloadHosts = const {},
  });

  final UpdateManifestSignatureMode signatureMode;
  final String hmacSecret;
  final bool requireSha256;
  final bool requireHttpsDownloadUrl;
  final Set<String> allowedDownloadHosts;
}

class UpdateManifestVerificationResult {
  const UpdateManifestVerificationResult({
    required this.passed,
    required this.message,
    required this.expected,
    required this.actual,
  });

  final bool passed;
  final String message;
  final String expected;
  final String actual;
}

UpdateManifestSignatureMode updateSignatureModeFromName(String value) {
  switch (value.trim().toLowerCase().replaceAll('-', '_')) {
    case 'none':
      return UpdateManifestSignatureMode.none;
    case 'hmac_sha256':
    case 'hmacsha256':
      return UpdateManifestSignatureMode.hmacSha256;
    case 'sha256':
    default:
      return UpdateManifestSignatureMode.sha256;
  }
}

String updateSignatureModeName(UpdateManifestSignatureMode mode) {
  switch (mode) {
    case UpdateManifestSignatureMode.none:
      return 'none';
    case UpdateManifestSignatureMode.sha256:
      return 'sha256';
    case UpdateManifestSignatureMode.hmacSha256:
      return 'hmac_sha256';
  }
}

dynamic _canonicalizeJsonValue(dynamic value) {
  if (value is Map) {
    final entries = <MapEntry<String, dynamic>>[];
    value.forEach((key, val) {
      entries.add(MapEntry(key.toString(), val));
    });
    entries.sort((a, b) => a.key.compareTo(b.key));

    final result = <String, dynamic>{};
    for (final entry in entries) {
      result[entry.key] = _canonicalizeJsonValue(entry.value);
    }
    return result;
  }

  if (value is List) {
    return value.map(_canonicalizeJsonValue).toList(growable: false);
  }

  return value;
}

String updateManifestCanonicalJson(dynamic value) {
  return jsonEncode(_canonicalizeJsonValue(value));
}

String updateManifestSha256Hex(String text) {
  return sha256.convert(utf8.encode(text)).toString();
}

String updateManifestHmacSha256Hex(String text, String secret) {
  final mac = Hmac(sha256, utf8.encode(secret));
  return mac.convert(utf8.encode(text)).toString();
}

/// check 接口在**签名之后**追加的运行时字段，不参与 HMAC 正文。
///
/// 服务端 `build_manifest()` 只对发布字段算 HMAC，随后 check 接口按当前
/// 请求方的版本号补上这些结论字段。客户端若对整个响应算 HMAC，必然算出
/// 不同的值，导致「更新清单签名不匹配」。
///
/// 这里用**固定白名单**而不是「差集」：如果按「服务端没签的就剥掉」来实现，
/// 攻击者只要多塞一个字段就能把它排除在校验之外。
const Set<String> updateManifestRuntimeFields = <String>{
  'currentVersionCode',
  'hasNewVersion',
  'updateRequired',
  'effectiveForceUpdate',
  'deviceId',
  'userId',
};

Map<String, dynamic> updateManifestSignaturePayload(
  Map<String, dynamic> manifestJson,
) {
  final payload = Map<String, dynamic>.from(manifestJson)
    ..remove('signature')
    ..remove('signatureAlgorithm')
    ..removeWhere((key, _) => updateManifestRuntimeFields.contains(key));
  return payload;
}

UpdateManifestVerificationResult verifyUpdateManifestSignature({
  required Map<String, dynamic> manifestJson,
  required UpdateManifestSecurityConfig security,
}) {
  if (security.signatureMode == UpdateManifestSignatureMode.none) {
    return const UpdateManifestVerificationResult(
      passed: true,
      message: '验签关闭',
      expected: '',
      actual: '',
    );
  }

  final actual = manifestJson['signature']?.toString().trim().toLowerCase() ?? '';
  if (actual.isEmpty) {
    return const UpdateManifestVerificationResult(
      passed: false,
      message: '更新清单缺少 signature',
      expected: '',
      actual: '',
    );
  }

  final manifestMode = updateSignatureModeFromName(
    manifestJson['signatureAlgorithm']?.toString() ?? '',
  );
  if (manifestMode != security.signatureMode) {
    return UpdateManifestVerificationResult(
      passed: false,
      message: '更新清单签名算法不匹配',
      expected: updateSignatureModeName(security.signatureMode),
      actual: updateSignatureModeName(manifestMode),
    );
  }

  final canonical = updateManifestCanonicalJson(
    updateManifestSignaturePayload(manifestJson),
  );

  String expected;
  switch (security.signatureMode) {
    case UpdateManifestSignatureMode.none:
      expected = '';
      break;
    case UpdateManifestSignatureMode.sha256:
      expected = updateManifestSha256Hex(canonical);
      break;
    case UpdateManifestSignatureMode.hmacSha256:
      if (security.hmacSecret.trim().isEmpty) {
        return const UpdateManifestVerificationResult(
          passed: false,
          message: 'HMAC 更新验签缺少 secret',
          expected: '',
          actual: '',
        );
      }
      expected = updateManifestHmacSha256Hex(canonical, security.hmacSecret);
      break;
  }

  final passed = actual == expected.toLowerCase();
  return UpdateManifestVerificationResult(
    passed: passed,
    message: passed ? '验签通过' : '更新清单签名不匹配',
    expected: expected,
    actual: actual,
  );
}

bool isValidSha256Hex(String value) {
  return RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value.trim());
}

String normalizeSha256Hex(String value) => value.trim().toLowerCase();

bool isValidUpdateDownloadUrl(
  String url, {
  bool requireHttps = true,
  Set<String> allowedHosts = const {},
}) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
  if (requireHttps && uri.scheme.toLowerCase() != 'https') return false;
  if (!requireHttps && uri.scheme.toLowerCase() != 'https' && uri.scheme.toLowerCase() != 'http') {
    return false;
  }

  final host = uri.host.toLowerCase();
  if (host == 'localhost' || host == '::1' || host.startsWith('127.')) {
    return false;
  }

  final normalizedAllowed = allowedHosts
      .map((host) => host.trim().toLowerCase())
      .where((host) => host.isNotEmpty)
      .toSet();
  if (normalizedAllowed.isEmpty) return true;

  return normalizedAllowed.any(
    (allowed) => host == allowed || host.endsWith('.$allowed'),
  );
}

void validateUpdateDownloadUrl(
  String url, {
  bool requireHttps = true,
  Set<String> allowedHosts = const {},
}) {
  if (!isValidUpdateDownloadUrl(
    url,
    requireHttps: requireHttps,
    allowedHosts: allowedHosts,
  )) {
    throw Exception('更新包下载地址无效或不受信任');
  }
}

void validateUpdateManifestSecurity({
  required UpdateManifest manifest,
  required Map<String, dynamic> rawManifestJson,
  required UpdateManifestSecurityConfig security,
}) {
  validateUpdateDownloadUrl(
    manifest.downloadUrl,
    requireHttps: security.requireHttpsDownloadUrl,
    allowedHosts: security.allowedDownloadHosts,
  );

  final expectedSha256 = manifest.sha256?.trim() ?? '';
  if (security.requireSha256 && !isValidSha256Hex(expectedSha256)) {
    throw Exception('更新清单缺少有效的 SHA-256 校验值');
  }

  final verify = verifyUpdateManifestSignature(
    manifestJson: rawManifestJson,
    security: security,
  );
  if (!verify.passed) {
    throw Exception(verify.message);
  }
}

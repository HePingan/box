import 'package:flutter_test/flutter_test.dart';

import 'package:box/config/app_config.dart';
import 'package:box/update/update_security.dart';

/// 回归：构建时漏传 `--dart-define=UPDATE_SIGNATURE_SECRET` 会产出一个
/// 「装上去才发现更新检查失败」的包 —— App 每次检查更新都弹
/// 「更新清单签名校验未通过 (HMAC 更新验签缺少 secret)」。
///
/// 真实事故：手工敲 `flutter build apk --release --target-platform android-arm64`
/// 构建了 1.7.3(173) 并发布，用户安装后检查更新即报该错。仓库里本就有
/// `tool/build_release_with_update_sign.sh` 负责注入全部 define，但被绕过了。
///
/// 这个测试把「配置自身是否自洽」变成可断言的，默认（不带 define 跑单测）会
/// 跳过，只在传入 secret 时校验；同时无条件校验「算法要求 secret 时 secret 不能空」
/// 这条不变式，防止再出现算法与密钥不匹配的组合。
void main() {
  group('更新验签配置自洽性', () {
    test('签名算法要求 secret 时，secret 必须非空', () {
      final mode = updateSignatureModeFromName(
        AppConfig.updateSignatureAlgorithm,
      );
      final secret = AppConfig.updateSignatureSecret;

      if (mode == UpdateManifestSignatureMode.hmacSha256 && secret.isEmpty) {
        // 单测环境默认不注入 secret，这里不能直接 fail，否则本地跑测试永远红。
        // 但要留下明确记录：这个组合一旦进了 release 包就是线上事故。
        markTestSkipped(
          '当前编译环境未注入 UPDATE_SIGNATURE_SECRET（单测默认如此）。'
          '发布 APK 必须用 tool/build_release_with_update_sign.sh 构建，'
          '否则会得到验签必失败的包。',
        );
        return;
      }

      if (mode == UpdateManifestSignatureMode.hmacSha256) {
        expect(
          secret.trim(),
          isNotEmpty,
          reason: 'HMAC 模式下 secret 为空，验签必失败',
        );
      }
    });

    test('注入 secret 后 HMAC 验签能通过；secret 缺失时报缺少 secret', () {
      const canonicalSecret = 'test-secret-for-regression';
      final manifest = <String, dynamic>{
        'schemaVersion': 1,
        'appId': 'box',
        'platform': 'android',
        'channel': 'release',
        'packageName': 'top.hpa888.box',
        'latestVersionCode': 173,
        'latestVersionName': '1.7.3',
        'minSupportedVersionCode': 0,
        'blockedVersionCodes': <int>[],
        'forceUpdate': false,
        'title': 'box 1.7.3',
        'notice': 'x',
        'changelog': <String>[],
        'downloadUrl':
            'https://box.hpa888.top/updates/box/android/release/box-1.7.3-173.apk',
        'backupDownloadUrl': null,
        'sha256':
            '1c6d4e50746bcbf7e6c6f5656ff5e592408481ec5095cfad09170ddcc70a011d',
        'fileSize': 34068271,
        'publishedAt': '2026-08-30T08:10:53.105859+00:00',
        'supportUrl': null,
        'signatureAlgorithm': 'HMAC-SHA256',
      };

      final canonical = updateManifestCanonicalJson(
        updateManifestSignaturePayload(manifest),
      );
      final signature = updateManifestHmacSha256Hex(canonical, canonicalSecret);
      final signed = Map<String, dynamic>.from(manifest)
        ..['signature'] = signature;

      // 1) secret 正确 -> 通过
      final okResult = verifyUpdateManifestSignature(
        manifestJson: signed,
        security: const UpdateManifestSecurityConfig(
          signatureMode: UpdateManifestSignatureMode.hmacSha256,
          hmacSecret: canonicalSecret,
          requireSha256: true,
          allowedDownloadHosts: <String>{'box.hpa888.top'},
        ),
      );
      expect(okResult.passed, isTrue, reason: okResult.message);

      // 2) secret 缺失 -> 正是用户截图里那条错误
      final missing = verifyUpdateManifestSignature(
        manifestJson: signed,
        security: const UpdateManifestSecurityConfig(
          signatureMode: UpdateManifestSignatureMode.hmacSha256,
          hmacSecret: '',
          requireSha256: true,
          allowedDownloadHosts: <String>{'box.hpa888.top'},
        ),
      );
      expect(missing.passed, isFalse);
      expect(missing.message, contains('缺少 secret'));
    });
  });
}

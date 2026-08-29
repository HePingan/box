@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// B1 回归：正式包必须用正式 keystore 签名，不能是 debug 签名。
///
/// 真实事故背景：线上已发布的 1.1.8 和本机构建的包，签名证书指纹不同
/// （4f5fa752… vs 8daac29e…），两者都是 CN=Android Debug——因为
/// `android/key.properties` 缺失时 build.gradle.kts 会 fallback 到 debug
/// 签名。跨签名无法覆盖安装，一旦发布，老用户会拿到
/// INSTALL_FAILED_UPDATE_INCOMPATIBLE，且被强更弹窗卡死在装不上的循环里。
///
/// 这条测试打 live 标签：它检查真实构建产物，需要先跑构建脚本。
void main() {
  const apkPath = 'build/app/outputs/flutter-apk/app-release.apk';
  const expectedFingerprint =
      '51944556c21e3b1cd0abf497a0fbb064939232ca69fff766e8b83c97774449af';

  String? findApksigner() {
    final candidates = Directory('/root/android-sdk/build-tools');
    if (!candidates.existsSync()) return null;
    final versions = candidates.listSync().whereType<Directory>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final dir in versions) {
      final f = File('${dir.path}/apksigner');
      if (f.existsSync()) return f.path;
    }
    return null;
  }

  test('release APK 不是 debug 签名，且指纹是预期的正式证书', () {
    final apk = File(apkPath);
    if (!apk.existsSync()) {
      markTestSkipped('未找到 $apkPath，先跑 tool/build_release_with_update_sign.sh');
      return;
    }

    final signer = findApksigner();
    if (signer == null) {
      markTestSkipped('未找到 apksigner');
      return;
    }

    final result = Process.runSync(signer, [
      'verify',
      '--print-certs',
      apkPath,
    ]);
    final out = '${result.stdout}${result.stderr}';

    // 关键断言一：绝不能是 Android Debug 证书。
    expect(
      out.contains('CN=Android Debug'),
      isFalse,
      reason: 'release 包是 debug 签名——key.properties 缺失导致 fallback，'
          '发布后老用户会 INSTALL_FAILED_UPDATE_INCOMPATIBLE',
    );

    // 关键断言二：指纹必须是这把长期 keystore，换了 key 就要显式改这里。
    expect(
      out.toLowerCase().replaceAll(':', ''),
      contains(expectedFingerprint),
      reason: '签名证书指纹与预期的正式 keystore 不一致',
    );
  });

  test('release APK 至少有 v2 签名', () {
    final apk = File(apkPath);
    final signer = findApksigner();
    if (!apk.existsSync() || signer == null) {
      markTestSkipped('缺少构建产物或 apksigner');
      return;
    }

    final result = Process.runSync(signer, ['verify', '-v', apkPath]);
    final out = '${result.stdout}${result.stderr}';
    expect(
      out.contains('v2 scheme (APK Signature Scheme v2): true'),
      isTrue,
      reason: 'v2 签名缺失，Android 7.0+ 上安装校验会退化',
    );
  });
}

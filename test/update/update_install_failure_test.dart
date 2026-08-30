import 'package:flutter_test/flutter_test.dart';

import 'package:box/update/update_install_failure.dart';

void main() {
  group('classifyInstallFailure', () {
    test('系统拒绝安装（签名不一致）归为不可恢复', () {
      // 真实场景：1.6.9 换了正式签名证书，老用户装的是旧 debug 证书包。
      // 系统会直接拒绝覆盖安装，重试一万次都是同样结果。
      final f = classifyInstallFailure(
        Exception('系统拒绝安装: INSTALL_FAILED_UPDATE_INCOMPATIBLE'),
      );
      expect(f.isUnrecoverable, isTrue);
      expect(f.needsManualReinstall, isTrue);
    });

    test('签名证书不一致的英文原文也能识别', () {
      final f = classifyInstallFailure(
        Exception('INSTALL_FAILED_SHARED_USER_INCOMPATIBLE'),
      );
      expect(f.isUnrecoverable, isTrue);
      expect(f.needsManualReinstall, isTrue);
    });

    test('网络失败是可重试的，不该劝用户卸载重装', () {
      final f = classifyInstallFailure(
        Exception('Connection closed before full header was received'),
      );
      expect(f.isUnrecoverable, isFalse);
      expect(f.needsManualReinstall, isFalse);
    });

    test('校验失败可重试（可能只是下载损坏）', () {
      final f = classifyInstallFailure(Exception('APK 校验失败，文件可能损坏或被篡改'));
      expect(f.isUnrecoverable, isFalse);
      expect(f.needsManualReinstall, isFalse);
    });

    test('不可恢复失败要给出人能看懂的指引，且包含备份提示', () {
      final f = classifyInstallFailure(
        Exception('系统拒绝安装: INSTALL_FAILED_UPDATE_INCOMPATIBLE'),
      );
      expect(f.guidance, contains('卸载'));
      expect(f.guidance, contains('备份'));
    });

    test('可重试失败的指引不提卸载，避免误导用户丢数据', () {
      final f = classifyInstallFailure(Exception('timeout'));
      expect(f.guidance, isNot(contains('卸载')));
    });
  });
}

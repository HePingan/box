import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 回归：发布脚本必须在**产物**上核对验签密钥。
///
/// 为什么需要这条测试：`update_signature_secret_present_test.dart` 检查的是
/// 「当前编译环境的 AppConfig 是否自洽」，而单测跑在没注入 --dart-define 的
/// 环境里，那条断言只会 markTestSkipped，结构上不可能拦住发布事故。
///
/// 事故发生过两次（1.7.3+173、1.8.5+185）：都是绕开
/// `tool/build_release_with_update_sign.sh` 手工敲 `flutter build apk --release`
/// 发出去的。用户装上后每次检查更新都报「更新清单签名校验未通过
/// (HMAC 更新验签缺少 secret)」，并且收不到任何后续版本 —— 更新链路是断的。
///
/// 密钥经 `--dart-define` 编译进 Dart 常量，最终落在 libapp.so 里，所以
/// 「传了 define」不等于「密钥进了包」，必须在产物上验。这条测试守的是
/// 那道闸门不被删掉或改弱。
void main() {
  group('发布脚本的验签密钥闸门', () {
    final script = File('tool/build_release_with_update_sign.sh');

    test('脚本存在且可读', () {
      expect(
        script.existsSync(),
        isTrue,
        reason: '发布脚本缺失，发布流程将退回手工 flutter build，事故会重演',
      );
    });

    test('构建后会在 libapp.so 里核对密钥，缺失则以非零码退出', () {
      final body = script.readAsStringSync();

      // 必须从 APK 里取出 libapp.so 来查，而不是只检查 shell 变量非空。
      expect(
        body,
        contains('libapp.so'),
        reason: '闸门没有检查产物内的 libapp.so，只看变量挡不住 define 没生效的情况',
      );
      expect(
        body.contains(r'grep -qF "$SECRET"'),
        isTrue,
        reason: '闸门必须在 libapp.so 内实搜密钥内容',
      );

      // 检查失败必须中断发布，不能只打印警告。
      final gateStart = body.indexOf('验签密钥闸门');
      expect(gateStart, greaterThan(-1), reason: '找不到验签密钥闸门段落');
      final gateEnd = body.indexOf('符号表闸门', gateStart);
      final gate = body.substring(
        gateStart,
        gateEnd > gateStart ? gateEnd : body.length,
      );
      expect(
        gate,
        contains('exit 1'),
        reason: '密钥缺失时必须中断构建，仅打印警告会让坏包流到发布环节',
      );
    });

    test('闸门只在 HMAC 模式下生效，避免 none/sha256 模式误报', () {
      final body = script.readAsStringSync();
      final gateStart = body.indexOf('验签密钥闸门');
      final gate = body.substring(gateStart);
      expect(
        gate.contains(r'"$SIG_ALGO" == "hmac_sha256"'),
        isTrue,
        reason: '闸门应按签名算法启用，否则关闭验签时会误拦',
      );
    });
  });
}

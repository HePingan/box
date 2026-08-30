import 'package:box/update/update_check_outcome.dart';
import 'package:box/update/update_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// A4 回归：手动检查更新必须能说出「为什么失败」。
///
/// 真实背景：`update_service.dart` 原来是 `catch (_)`，任何失败都被吞掉，
/// 加上 allowProceedOnCheckFailure 默认 true，验签失败在 UI 上完全静默——
/// 这正是 HMAC 口径 bug 能长期存活没人发现的原因。
UpdateManifest manifestWithCode(int code) {
  return UpdateManifest.fromJson(<String, dynamic>{
    'appId': 'box',
    'platform': 'android',
    'channel': 'release',
    'packageName': 'top.hpa888.box',
    'latestVersionCode': code,
    'latestVersionName': '1.$code.0',
    'downloadUrl': 'https://box.hpa888.top/a.apk',
    'sha256': 'a' * 64,
  });
}

void main() {
  group('结论分类', () {
    test('有更新', () {
      final o = UpdateCheckOutcome.fromManifest(
        manifest: manifestWithCode(200),
        currentVersionCode: 169,
      );
      expect(o.status, UpdateCheckStatus.updateAvailable);
      expect(o.manifest, isNotNull);
      expect(o.describe(), contains('1.200.0'));
    });

    test('已是最新', () {
      final o = UpdateCheckOutcome.fromManifest(
        manifest: manifestWithCode(169),
        currentVersionCode: 169,
      );
      expect(o.status, UpdateCheckStatus.upToDate);
      expect(o.describe(), contains('已是最新'));
    });

    test('后台版本比本机旧也算已是最新，不能提示更新', () {
      // 真实数据：后台最新发布 118，工程已 169。
      final o = UpdateCheckOutcome.fromManifest(
        manifest: manifestWithCode(118),
        currentVersionCode: 169,
      );
      expect(o.status, UpdateCheckStatus.upToDate);
    });
  });

  group('失败原因可读', () {
    test('验签失败有明确文案且带原始信息', () {
      final o = UpdateCheckOutcome.failure(
        UpdateCheckStatus.signatureRejected,
        detail: '更新清单签名不匹配',
      );
      expect(o.status, UpdateCheckStatus.signatureRejected);
      final text = o.describe();
      expect(text, contains('签名'));
      expect(text, contains('更新清单签名不匹配'));
      expect(o.manifest, isNull);
    });

    test('网络失败与验签失败区分开', () {
      final net = UpdateCheckOutcome.failure(
        UpdateCheckStatus.networkError,
        detail: 'Connection timeout',
      );
      expect(net.describe(), contains('网络'));
      expect(net.describe(), isNot(contains('签名')));
    });

    test('每种状态都有非空描述', () {
      for (final s in UpdateCheckStatus.values) {
        final o =
            s == UpdateCheckStatus.updateAvailable ||
                s == UpdateCheckStatus.upToDate
            ? UpdateCheckOutcome.fromManifest(
                manifest: manifestWithCode(
                  s == UpdateCheckStatus.updateAvailable ? 999 : 1,
                ),
                currentVersionCode: 169,
              )
            : UpdateCheckOutcome.failure(s, detail: 'x');
        expect(o.describe().trim(), isNotEmpty, reason: '$s 描述为空');
      }
    });

    test('detail 为空时描述仍然可读', () {
      final o = UpdateCheckOutcome.failure(UpdateCheckStatus.networkError);
      expect(o.describe().trim(), isNotEmpty);
    });
  });
}

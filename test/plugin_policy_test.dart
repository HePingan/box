import 'package:box/features/policy/plugin_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PluginPolicySnapshot.denialFor', () {
    test('allows by default when version fresh', () {
      final snap = PluginPolicySnapshot(
        version: 1,
        ttlSec: 300,
        fetchedAt: DateTime.now(),
        pluginsAllowed: true,
        globalMessage: '',
        minAppVersion: '',
        forceLogout: false,
        plugins: const {},
        userPluginsAllowed: true,
        deniedPluginIds: const {},
        userMessage: '',
      );
      expect(snap.canUse(PluginIds.quizAnswer), isTrue);
    });

    test('global pluginsAllowed=false denies all high-risk', () {
      final snap = PluginPolicySnapshot(
        version: 2,
        ttlSec: 300,
        fetchedAt: DateTime.now(),
        pluginsAllowed: false,
        globalMessage: '维护中',
        minAppVersion: '',
        forceLogout: false,
        plugins: const {},
        userPluginsAllowed: true,
        deniedPluginIds: const {},
        userMessage: '',
      );
      expect(snap.denialFor(PluginIds.quizAnswer), '维护中');
    });

    test('user denied plugin id', () {
      final snap = PluginPolicySnapshot(
        version: 3,
        ttlSec: 300,
        fetchedAt: DateTime.now(),
        pluginsAllowed: true,
        globalMessage: '',
        minAppVersion: '',
        forceLogout: false,
        plugins: const {},
        userPluginsAllowed: true,
        deniedPluginIds: {PluginIds.quizAnswer},
        userMessage: '账号未授权答题',
      );
      expect(snap.denialFor(PluginIds.quizAnswer), '账号未授权答题');
      expect(snap.canUse(PluginIds.quizEntry), isTrue);
    });

    test('feature-level deny cloud_push', () {
      final snap = PluginPolicySnapshot(
        version: 4,
        ttlSec: 300,
        fetchedAt: DateTime.now(),
        pluginsAllowed: true,
        globalMessage: '',
        minAppVersion: '',
        forceLogout: false,
        plugins: {
          PluginIds.quizBankView: const PluginPolicyEntry(
            allowed: true,
            message: '停投稿',
            features: {
              PluginFeature.cloudPush: false,
              PluginFeature.cloudPull: true,
              PluginFeature.view: true,
            },
          ),
        },
        userPluginsAllowed: true,
        deniedPluginIds: const {},
        userMessage: '',
      );
      expect(
        snap.denialFor(
          PluginIds.quizBankView,
          feature: PluginFeature.cloudPush,
        ),
        '停投稿',
      );
      expect(
        snap.canUse(
          PluginIds.quizBankView,
          feature: PluginFeature.cloudPull,
        ),
        isTrue,
      );
    });

    test('expired cache denies high-risk', () {
      final snap = PluginPolicySnapshot(
        version: 5,
        ttlSec: 60,
        fetchedAt: DateTime.now().subtract(const Duration(minutes: 10)),
        pluginsAllowed: true,
        globalMessage: '',
        minAppVersion: '',
        forceLogout: false,
        plugins: const {},
        userPluginsAllowed: true,
        deniedPluginIds: const {},
        userMessage: '',
      );
      expect(snap.isExpired, isTrue);
      expect(
        snap.denialFor(PluginIds.quizAnswer, highRisk: true),
        contains('过期'),
      );
      // 低风险（仅打开配置页）不过期拦截
      expect(
        snap.canUse(PluginIds.quizAnswer, highRisk: false),
        isTrue,
      );
    });

    test('never-fetched does not treat as expired', () {
      final snap = PluginPolicySnapshot.allowAll();
      expect(snap.isExpired, isFalse);
      expect(snap.canUse(PluginIds.quizAnswer, highRisk: true), isTrue);
    });

    test('fromJson client payload', () {
      final snap = PluginPolicySnapshot.fromJson({
        'version': 9,
        'ttlSec': 120,
        'forceLogout': false,
        'global': {'pluginsAllowed': true, 'message': ''},
        'plugins': {
          PluginIds.quizAnswer: {
            'allowed': false,
            'message': '答题停用',
            'features': {'overlay': false},
          },
        },
        'user': {
          'pluginsAllowed': true,
          'deniedPluginIds': <String>[],
          'message': '',
        },
      }, fetchedAt: DateTime.now());
      expect(snap.version, 9);
      expect(snap.denialFor(PluginIds.quizAnswer), '答题停用');
    });
  });
}

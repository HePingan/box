import 'package:box/features/disguise/domain/disguise_session.dart';
import 'package:box/features/disguise/domain/disguise_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<DisguiseSettings> makeSettings() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return DisguiseSettings(prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('默认值', () {
    test('默认不开伪装、没有口令', () async {
      final settings = await makeSettings();
      expect(settings.enabled, isFalse);
      expect(settings.hasPin, isFalse);
      expect(settings.verifyPin('1234'), isFalse);
    });

    test('默认触发方式是「输完按 =」，自动上锁 5 分钟，遮缩略图关', () async {
      final settings = await makeSettings();
      expect(settings.trigger, DisguiseTrigger.equals);
      expect(settings.relockMinutes, DisguiseSettings.defaultRelockMinutes);
      // 关：真计算器不设 FLAG_SECURE，默认开着会在最近任务里露出空卡片这一破绽
      expect(settings.secureRecents, isFalse);
    });
  });

  group('口令', () {
    test('设置后可校验，错的口令不通过', () async {
      final settings = await makeSettings();
      expect(await settings.setPin('2468'), isTrue);
      expect(settings.hasPin, isTrue);
      expect(settings.verifyPin('2468'), isTrue);
      expect(settings.verifyPin('2469'), isFalse);
      expect(settings.verifyPin(''), isFalse);
    });

    test('非法口令设置失败且不落盘', () async {
      final settings = await makeSettings();
      expect(await settings.setPin('123'), isFalse);
      expect(await settings.setPin('abcd'), isFalse);
      expect(settings.hasPin, isFalse);
    });

    test('改口令后旧口令立刻失效', () async {
      final settings = await makeSettings();
      await settings.setPin('1111');
      await settings.setPin('2222');
      expect(settings.verifyPin('1111'), isFalse);
      expect(settings.verifyPin('2222'), isTrue);
    });
  });

  group('恢复码', () {
    test('默认没有恢复码', () async {
      final settings = await makeSettings();
      expect(settings.hasRecoveryCode, isFalse);
      expect(settings.verifyRecoveryCode('K7QT-M2XR-9WPD-4FZG'), isFalse);
    });

    test('发码后可校验，且明文不再存在', () async {
      final settings = await makeSettings();
      final code = await settings.issueRecoveryCode();
      expect(code, isNotNull);
      expect(settings.hasRecoveryCode, isTrue);
      expect(settings.verifyRecoveryCode(code!), isTrue);

      // 关键：落盘的是摘要，不是明文。直接把 prefs 摊开看。
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs
          .getKeys()
          .map((key) => prefs.get(key).toString())
          .join();
      expect(raw.contains(code), isFalse);
      expect(raw.contains(code.replaceAll('-', '')), isFalse);
    });

    test('大小写 / 空格 / 去掉连字符都能通过', () async {
      final settings = await makeSettings();
      final code = await settings.issueRecoveryCode();
      expect(
        settings.verifyRecoveryCode(code!.replaceAll('-', '').toLowerCase()),
        isTrue,
      );
      expect(settings.verifyRecoveryCode(code.replaceAll('-', ' ')), isTrue);
    });

    test('错一位、空串、别处的码都不通过', () async {
      final settings = await makeSettings();
      final code = await settings.issueRecoveryCode();
      final tail = code!.substring(0, code.length - 1);
      final flipped = code.endsWith('2') ? '3' : '2';
      expect(settings.verifyRecoveryCode('$tail$flipped'), isFalse);
      expect(settings.verifyRecoveryCode(''), isFalse);
      expect(settings.verifyRecoveryCode('   '), isFalse);

      final other = await makeSettings();
      expect(other.verifyRecoveryCode(code), isFalse);
    });

    test('重新发码后旧码立刻失效', () async {
      final settings = await makeSettings();
      final old = await settings.issueRecoveryCode();
      final fresh = await settings.issueRecoveryCode();
      expect(fresh, isNot(old));
      expect(settings.verifyRecoveryCode(old!), isFalse);
      expect(settings.verifyRecoveryCode(fresh!), isTrue);
    });

    test('清掉恢复码后不能再用', () async {
      final settings = await makeSettings();
      final code = await settings.issueRecoveryCode();
      await settings.clearRecoveryCode();
      expect(settings.hasRecoveryCode, isFalse);
      expect(settings.verifyRecoveryCode(code!), isFalse);
    });

    test('恢复码与口令互不影响', () async {
      final settings = await makeSettings();
      await settings.setPin('2468');
      final code = await settings.issueRecoveryCode();
      expect(settings.verifyPin('2468'), isTrue);
      expect(settings.verifyRecoveryCode(code!), isTrue);
      // 用恢复码重设口令：恢复码仍然有效（轮换由调用方另外做）。
      await settings.setPin('1357');
      expect(settings.verifyPin('1357'), isTrue);
      expect(settings.verifyPin('2468'), isFalse);
      expect(settings.verifyRecoveryCode(code), isTrue);
    });
  });

  group('开关与档位', () {
    test('伪装开关可往返', () async {
      final settings = await makeSettings();
      await settings.setEnabled(true);
      expect(settings.enabled, isTrue);
      await settings.setEnabled(false);
      expect(settings.enabled, isFalse);
    });

    test('触发方式可切换', () async {
      final settings = await makeSettings();
      await settings.setTrigger(DisguiseTrigger.longPress);
      expect(settings.trigger, DisguiseTrigger.longPress);
    });

    test('自动上锁时长被夹在 0–120 分钟', () async {
      final settings = await makeSettings();
      await settings.setRelockMinutes(999);
      expect(settings.relockMinutes, 120);
      await settings.setRelockMinutes(-5);
      expect(settings.relockMinutes, 0);
    });
  });

  group('进程内解锁状态', () {
    test('上锁/解锁会通知监听者', () {
      final session = DisguiseSession();
      var notified = 0;
      session.addListener(() => notified++);
      expect(session.unlocked, isFalse);
      session.unlock();
      expect(session.unlocked, isTrue);
      expect(notified, 1);
      session.lock();
      expect(session.unlocked, isFalse);
      expect(notified, 2);
      // 重复设置同一状态不该额外通知（避免无意义重建）。
      session.lock();
      expect(notified, 2);
    });

    test('切后台超过设定时长才上锁', () {
      final session = DisguiseSession()..unlock();
      session.markBackgrounded(
        DateTime.now().subtract(const Duration(minutes: 6)),
      );
      expect(session.lockIfIdle(5), isTrue);
      expect(session.unlocked, isFalse);
    });

    test('时长没到不上锁；0 表示关闭自动上锁', () {
      final session = DisguiseSession()..unlock();
      session.markBackgrounded(
        DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(session.lockIfIdle(5), isFalse);
      expect(session.unlocked, isTrue);

      session.markBackgrounded(
        DateTime.now().subtract(const Duration(hours: 9)),
      );
      expect(session.lockIfIdle(0), isFalse);
      expect(session.unlocked, isTrue);
    });

    test('回到前台会清掉后台时刻', () {
      final session = DisguiseSession()..unlock();
      session.markBackgrounded(
        DateTime.now().subtract(const Duration(hours: 2)),
      );
      session.markForeground();
      expect(session.lockIfIdle(1), isFalse);
      expect(session.unlocked, isTrue);
    });
  });
}

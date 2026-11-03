import 'package:shared_preferences/shared_preferences.dart';

import 'pin_digest.dart' as digest;

/// 伪装（把本应用变成一支计算器）的持久化设置。
///
/// 与 `LegalConsentStore` 同一形状：构造时注入 `SharedPreferences`，
/// 因此可以在 widget/unit 测试里用 `setMockInitialValues` 直接构造，
/// 不需要真实的 Android 环境。
///
/// ## 安全口径（写在这里，也要写进 UI 文案）
///
/// 这里的口令只是一道「障眼法闸门」，**不是加密**：计算器界面挡住的是
/// 顺手拿起手机的人，挡不住 adb / root / 备份取证 —— 应用数据本身没有加密，
/// 任何有设备写权限的人都能绕过闸门直接读数据。所以：
/// - 口令只存 `sha256(salt:pin)`，不存明文（防止一眼看穿，也让「同一口令」
///   在不同设备上不可比对）；
/// - 校验走定长时间比较（`digest.constantTimeHexEquals`），不因前几位正确就早退，
///   避免 PIN 逐位被时序测出来；
/// - UI 里绝不允许出现「密码错误」字样（见 `CalculatorDisguisePage`）。
class DisguiseSettings {
  DisguiseSettings(this._prefs);

  final SharedPreferences _prefs;

  /// 是否已开启伪装。
  static const String enabledKey = 'disguise_enabled';

  /// 口令摘要（hex）与每安装随机盐。
  static const String pinHashKey = 'disguise_pin_hash';
  static const String pinSaltKey = 'disguise_pin_salt';

  /// 恢复码摘要（hex）与盐。恢复码只在生成那一刻显示一次，之后只留摘要。
  static const String recoveryHashKey = 'disguise_recovery_hash';
  static const String recoverySaltKey = 'disguise_recovery_salt';

  /// 切后台多少分钟后自动上锁。0 表示不自动上锁。
  static const String relockMinutesKey = 'disguise_relock_minutes';

  /// 解锁触发方式：`equals`（输口令后按 `=`，默认）或 `long_press`（长按 `=`）。
  static const String triggerKey = 'disguise_trigger';

  /// 是否用 FLAG_SECURE 遮住最近任务缩略图（会连带禁用截图）。
  static const String secureRecentsKey = 'disguise_secure_recents';

  /// 口令长度范围。实际定义在 [pin_digest]（那边是纯 Dart，能单独跑测试）。
  static const int minPinLength = digest.kMinPinLength;
  static const int maxPinLength = digest.kMaxPinLength;

  static const int defaultRelockMinutes = 5;

  bool get enabled => _prefs.getBool(enabledKey) ?? false;

  Future<bool> setEnabled(bool value) async {
    try {
      return await _prefs.setBool(enabledKey, value);
    } catch (_) {
      return false;
    }
  }

  bool get hasPin =>
      (_prefs.getString(pinHashKey)?.isNotEmpty ?? false) &&
      (_prefs.getString(pinSaltKey)?.isNotEmpty ?? false);

  DisguiseTrigger get trigger {
    final raw = _prefs.getString(triggerKey);
    return raw == DisguiseTrigger.longPress.storageValue
        ? DisguiseTrigger.longPress
        : DisguiseTrigger.equals;
  }

  Future<bool> setTrigger(DisguiseTrigger value) async {
    try {
      return await _prefs.setString(triggerKey, value.storageValue);
    } catch (_) {
      return false;
    }
  }

  int get relockMinutes =>
      _prefs.getInt(relockMinutesKey) ?? defaultRelockMinutes;

  Future<bool> setRelockMinutes(int minutes) async {
    try {
      return await _prefs.setInt(relockMinutesKey, minutes.clamp(0, 120));
    } catch (_) {
      return false;
    }
  }

  /// 默认 **关**：vivo 系统计算器（com.android.bbkcalculator 15.6.1.1）的
  /// Calculator.onCreate 里唯一的窗口标志操作是 clearFlags(FLAG_ALT_FOCUSABLE_IM,
  /// 即 131072)，它从不设 FLAG_SECURE。我们要装成它，默认开启反而制造破绽：
  /// 最近任务里本应用卡片会是空白，而真计算器有正常预览，两台机器一对比就露。
  ///
  /// 注意这是「隐蔽」与「隐私」的真实取舍，不是纯技术选择：开了更安全，但更像
  /// 一个被改过的应用。设置页把代价写在开关下面，交给用户自己决定。
  bool get secureRecents => _prefs.getBool(secureRecentsKey) ?? false;

  Future<bool> setSecureRecents(bool value) async {
    try {
      return await _prefs.setBool(secureRecentsKey, value);
    } catch (_) {
      return false;
    }
  }

  /// 设置（或修改）解锁口令。
  ///
  /// 每次设置都换一颗新盐：同一口令在两台设备上的摘要不同，换了口令也不会
  /// 暴露「和上次是不是同一个」。
  Future<bool> setPin(String pin) async {
    if (!isValidPin(pin)) return false;
    final salt = digest.randomSaltHex();
    final pinHash = digest.hashPin(salt, pin);
    try {
      final okHash = await _prefs.setString(pinHashKey, pinHash);
      final okSalt = await _prefs.setString(pinSaltKey, salt);
      return okHash && okSalt;
    } catch (_) {
      return false;
    }
  }

  /// 校验口令。**定长时间**：无论对错都算完同样的字节数。
  bool verifyPin(String pin) {
    final stored = _prefs.getString(pinHashKey);
    final salt = _prefs.getString(pinSaltKey);
    if (stored == null || salt == null) return false;
    return digest.constantTimeHexEquals(stored, digest.hashPin(salt, pin));
  }

  Future<void> clearPin() async {
    try {
      await _prefs.remove(pinHashKey);
      await _prefs.remove(pinSaltKey);
    } catch (_) {
      // 清不掉也不算致命：hasPin 会继续为 true，用户可再设一次覆盖。
    }
  }

  /// 是否已有可用恢复码。
  bool get hasRecoveryCode =>
      (_prefs.getString(recoveryHashKey)?.isNotEmpty ?? false) &&
      (_prefs.getString(recoverySaltKey)?.isNotEmpty ?? false);

  /// 生成一枚新恢复码并落盘，**返回明文供用户抄写**（此后只剩摘要）。
  ///
  /// 每次都换新盐；旧恢复码在同一刻失效 —— 这个函数本身就是"轮换"，
  /// 所以恢复成功之后也会再调它一次，把可能被旁人瞄到过的那枚作废。
  Future<String?> issueRecoveryCode() async {
    final code = digest.randomRecoveryCode();
    final salt = digest.randomSaltHex();
    try {
      // 存**归一化后**的串的摘要：显示给人看的是带连字符的版本，
      // 两者必须落到同一个摘要上，否则"自己发的码自己验不过"。
      final okHash = await _prefs.setString(
        recoveryHashKey,
        digest.hashPin(salt, digest.normalizeRecoveryCode(code)),
      );
      final okSalt = await _prefs.setString(recoverySaltKey, salt);
      if (!okHash || !okSalt) return null;
      return code;
    } catch (_) {
      return null;
    }
  }

  /// 校验恢复码。同样走**定长时间比较**，且输入先归一化（去空格/连字符/小写）。
  bool verifyRecoveryCode(String input) {
    final stored = _prefs.getString(recoveryHashKey);
    final salt = _prefs.getString(recoverySaltKey);
    if (stored == null || salt == null) return false;
    final normalized = digest.normalizeRecoveryCode(input);
    if (normalized.isEmpty) return false;
    return digest.constantTimeHexEquals(
      stored,
      digest.hashPin(salt, normalized),
    );
  }

  Future<void> clearRecoveryCode() async {
    try {
      await _prefs.remove(recoveryHashKey);
      await _prefs.remove(recoverySaltKey);
    } catch (_) {
      // 同 clearPin：清不掉也不致命，下次 issue 会覆盖。
    }
  }

  /// 口令合法性（长度 + 纯数字），转发到 [digest]。
  static bool isValidPin(String pin) => digest.isValidPin(pin);
}

/// 解锁触发方式。
enum DisguiseTrigger {
  /// 输完口令直接按 `=`。默认，最不容易被旁观者看出破绽。
  equals('equals', '输完口令按 ='),

  /// 长按 `=` 弹出口令框。更隐蔽，但长按本身是个可疑动作。
  longPress('long_press', '长按 = 输入口令');

  const DisguiseTrigger(this.storageValue, this.label);

  final String storageValue;
  final String label;
}

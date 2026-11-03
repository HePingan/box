import 'package:flutter/foundation.dart';

/// 进程内解锁状态。
///
/// 刻意**不持久化**：杀掉进程/重启手机就回到计算器界面 —— 这正是一次性会话
/// 该有的行为。把「已解锁」写进磁盘等于伪装只在第一次有效，之后随时点开都是
/// 真应用，伪装就白做了。
///
/// 用 [ChangeNotifier] 而不是全局变量：`DisguiseGate` 直接监听它，
/// 上锁/解锁只改一处状态，界面自动回到计算器或真应用，不需要各页面各自判断。
class DisguiseSession extends ChangeNotifier {
  DisguiseSession();

  /// 单例。App 内只有一份解锁状态，避免两个入口判出不同结果。
  static final DisguiseSession instance = DisguiseSession();

  bool _unlocked = false;
  DateTime? _backgroundedAt;

  bool get unlocked => _unlocked;

  /// 进入后台的时刻（用于「切后台 N 分钟后自动上锁」）。
  DateTime? get backgroundedAt => _backgroundedAt;

  void unlock() {
    if (_unlocked && _backgroundedAt == null) return;
    _unlocked = true;
    _backgroundedAt = null;
    notifyListeners();
  }

  void lock() {
    if (!_unlocked) return;
    _unlocked = false;
    _backgroundedAt = null;
    notifyListeners();
  }

  void markBackgrounded([DateTime? at]) {
    _backgroundedAt = at ?? DateTime.now();
  }

  void markForeground() {
    _backgroundedAt = null;
  }

  /// 若后台已超过 [minutes] 分钟则上锁，返回是否发生了上锁。
  ///
  /// [minutes] <= 0 表示关闭自动上锁。这里用「进入后台的时刻」判断而不是
  /// 定时器：手机深度睡眠时定时器根本不会按时跑，回到前台再算差值才可靠。
  bool lockIfIdle(int minutes) {
    if (minutes <= 0) return false;
    final since = _backgroundedAt;
    if (since == null) return false;
    if (DateTime.now().difference(since) >= Duration(minutes: minutes)) {
      lock();
      return true;
    }
    return false;
  }
}

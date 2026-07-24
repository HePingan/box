import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import './quiz_cloud_pull.dart';

/// 静默自动增量同步：启动/回前台触发，默认间隔 ≥ 6 小时。
class QuizCloudAutoSync {
  QuizCloudAutoSync._();

  static final QuizCloudAutoSync instance = QuizCloudAutoSync._();

  static const _enabledKey = 'quiz_cloud_auto_sync_enabled_v1';
  static const _minInterval = Duration(hours: 6);
  static const _startupDelay = Duration(seconds: 8);

  final QuizCloudPullCoordinator _pull = QuizCloudPullCoordinator();
  bool _running = false;
  DateTime? _lastAttemptAt;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  /// App 启动后延迟触发，避免阻塞首屏。
  void scheduleStartup() {
    unawaited(Future<void>.delayed(_startupDelay, () => maybeSync(reason: 'startup')));
  }

  /// 回前台时触发（由 lifecycle 调用）。
  Future<void> onAppResumed() => maybeSync(reason: 'resume');

  Future<QuizCloudPullResult?> maybeSync({
    String reason = 'manual',
    bool force = false,
  }) async {
    if (_running) return null;
    if (!force && !(await isEnabled())) return null;

    final status = await _pull.loadStatus();
    if (!force) {
      final last = status.lastSyncAt;
      if (last != null && DateTime.now().difference(last) < _minInterval) {
        return null;
      }
      // 冷却：避免 resume 抖动
      final attempted = _lastAttemptAt;
      if (attempted != null &&
          DateTime.now().difference(attempted) < const Duration(minutes: 10)) {
        return null;
      }
    }

    _running = true;
    _lastAttemptAt = DateTime.now();
    try {
      debugPrint('[QuizCloudAutoSync] start ($reason)');
      final result = await _pull.pullAll();
      debugPrint('[QuizCloudAutoSync] done: ${result.summaryText}');
      return result;
    } catch (e, st) {
      debugPrint('[QuizCloudAutoSync] failed: $e\n$st');
      return null;
    } finally {
      _running = false;
    }
  }

  void dispose() => _pull.dispose();
}

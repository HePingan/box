import 'package:flutter/foundation.dart';

/// 读屏用量（服务端在**响应头**里回报，B1 2026-10-01）。
///
/// 为什么不放 body：body 是 OpenAI 兼容结构（客户端按 chat/completions 解析），
/// 塞自定义字段会破坏解析；响应头对老客户端完全透明。
///
/// 服务端口径：账号/设备维度**每日 100 次**（`quizVisionDailyCap`）。此前客户端
/// 只有额度用完时的 429 才知道超了 —— 自检页据此显示「今日 X/100」，用户报障时
/// 一眼能看出是"没额度了"还是"卡住了"。
class QuizVisionUsage {
  QuizVisionUsage._();

  static int? usedToday;
  static int? dailyCap;
  static DateTime? updatedAt;

  /// 上游失败次数（2026-11-18 起失败不计额度，但要如实告诉用户"白试了几次"）。
  static int? failedToday;

  /// 额度重置时刻（服务端按 UTC 日界 ⇒ 北京时间每天 08:00）。
  static DateTime? resetsAt;

  /// 从响应头里取用量（**大小写不敏感**：Dart http 会把键名转小写，服务端发的是
  /// `X-Quiz-Vision-Used`，两边都要认）。老服务端没有这两个头时保持原值不动。
  static void record(Map<String, String> headers) {
    int? pick(String lower) {
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == lower) {
          final value = int.tryParse(entry.value.trim());
          if (value != null) return value;
        }
      }
      return null;
    }

    final used = pick('x-quiz-vision-used');
    final cap = pick('x-quiz-vision-cap');
    if (used == null && cap == null) return;
    usedToday = used ?? usedToday;
    dailyCap = cap ?? dailyCap;
    updatedAt = DateTime.now();
  }

  /// 给自检页与「复制结论」用的一行文字。
  static String describe() {
    if (usedToday == null) {
      return '未知（还没发过读屏请求，也未能从服务端查询）';
    }
    final reset = resetsAt == null ? '' : '，${_resetText(resetsAt!)}重置';
    final failed = (failedToday ?? 0) > 0 ? '；上游失败 $failedToday 次（不计额度）' : '';
    return '今日 $usedToday/${dailyCap ?? '?'} 次（服务端回报）$reset$failed';
  }

  static String _resetText(DateTime utc) {
    final local = utc.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  @visibleForTesting
  static void reset() {
    usedToday = null;
    dailyCap = null;
    updatedAt = null;
    failedToday = null;
    resetsAt = null;
  }
}

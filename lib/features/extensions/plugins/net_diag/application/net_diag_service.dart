// 网络诊断的门面：跑探测 + 记住最近查过的主机。
//
// 只做两件事：把 [NetDiagProbe] 包一层给界面用；把最近查询存本机
// （shared_preferences，零服务端）。历史记录存「用户原样输入」而不是解析结果
// —— 回填时要跟用户当初写的一模一样。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/net_diag_models.dart';
import '../domain/net_diag_probe.dart';

class NetDiagService {
  NetDiagService({NetDiagProbe? probe}) : probe = probe ?? NetDiagProbe();

  final NetDiagProbe probe;

  static const String recentKey = 'netDiag.recentTargets';
  static const int maxRecent = 5;

  /// 跑一轮全部检测。
  Future<NetDiagReport> diagnose(
    NetDiagTarget target, {
    void Function(NetDiagCheckResult)? onResult,
  }) async {
    final results = await probe.runAll(target, onResult: onResult);
    return NetDiagReport(
      target: target,
      results: results,
      startedAt: DateTime.now(),
    );
  }

  /// 最近查过的主机（新→旧）。读不出来就返回空表，不让首屏因此报错。
  Future<List<String>> loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(recentKey);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().take(maxRecent).toList();
    } catch (e) {
      // 存储读不了与「从没存过」现象一样（都空表），留一行痕以便区分。
      debugPrint('[net-diag] 最近查询读取失败，按空处理：$e');
      return const [];
    }
  }

  /// 记一次查询（去重、只留最近 [maxRecent] 条）。
  Future<void> rememberTarget(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await loadRecent();
      final next = <String>[
        text,
        ...current.where((e) => e != text),
      ].take(maxRecent).toList();
      await prefs.setString(recentKey, jsonEncode(next));
    } catch (e) {
      // 记不住历史不影响本次诊断结果，只留痕。
      debugPrint('[net-diag] 最近查询写入失败：$e');
    }
  }
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'update_check_outcome.dart';

/// 上一次更新检查的**结论 + 时间**。
///
/// 为什么要单独落盘（而不是读 `update_manifest_cache_v1`）：
///  - `UpdateCheckOutcome` 只在检查那一刻存在，用户是**后来**才打开关于页的；
///  - 清单缓存里只有清单本身，**没有任何时间戳**（`update_service.dart` 只写
///    `manifest.toJson()`），所以那时谁也答不出「上次什么时候检查、结果如何」。
///
/// 于是用户在关于页只能看到「当前版本」，不点一次「检查更新」就永远不知道线上
/// 是什么版本；而失败（网络不通 / 验签不通过）更是完全不可见 —— 这正是当年
/// 验签 bug 能长期静默存活的原因之一。
class UpdateLastCheck {
  const UpdateLastCheck({
    required this.at,
    required this.status,
    this.detail,
    this.latestVersionCode,
    this.latestVersionName,
  });

  final DateTime at;
  final UpdateCheckStatus status;

  /// 原始错误信息（不美化），与 [UpdateCheckOutcome.detail] 同口径。
  final String? detail;

  final int? latestVersionCode;
  final String? latestVersionName;

  /// 说法与检查当下**逐字一致**：复用 [describeUpdateCheckStatus]。
  String describe() => describeUpdateCheckStatus(
    status,
    latestVersionCode: latestVersionCode,
    latestVersionName: latestVersionName,
    detail: detail,
  );

  /// 「刚刚 / 3 分钟前 / 2 小时前 / 5 天前 / 2026-09-01」。
  ///
  /// 时间戳坏掉或来自未来时退回**具体日期**而不是编一个相对时间：
  /// 「0 分钟前」这种输出会让人以为是刚检查过。
  String ageText(DateTime now) {
    final diff = now.difference(at);
    if (diff.isNegative || diff.inMinutes < 1) {
      if (diff.isNegative) return _dateText();
      return '刚刚';
    }
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return _dateText();
  }

  String _dateText() =>
      '${at.year}-${at.month.toString().padLeft(2, '0')}'
      '-${at.day.toString().padLeft(2, '0')}';
}

/// 读写 [UpdateLastCheck]（SharedPreferences 一个 key，不参与备份）。
class UpdateLastCheckStore {
  const UpdateLastCheckStore._();

  static const String _key = 'update_last_check_v1';

  /// 每次检查结束都记一笔（唯一入口 `UpdateService.checkUpdateDiagnostic`）。
  ///
  /// 写失败不该影响检查本身：这里 `catch` 掉异常，最坏结果是关于页少一行状态。
  static Future<void> record(UpdateCheckOutcome outcome) async {
    try {
      final payload = <String, dynamic>{
        'at': DateTime.now().toIso8601String(),
        'status': outcome.status.name,
        if (outcome.detail != null) 'detail': outcome.detail,
        if (outcome.manifest != null)
          'latestCode': outcome.manifest!.latestVersionCode,
        if (outcome.manifest != null)
          'latestName': outcome.manifest!.latestVersionName,
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(payload));
    } catch (_) {
      // 记录状态是附加信息，失败不冒泡。
    }
  }

  /// 读不到 / 记录坏掉都返回 null（界面显示「还没检查过」），不猜也不抛。
  static Future<UpdateLastCheck?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return _parse(decoded);
    } catch (_) {
      return null;
    }
  }

  static UpdateLastCheck? _parse(Map<String, dynamic> json) {
    final atRaw = json['at'];
    final statusRaw = json['status'];
    if (atRaw is! String || statusRaw is! String) return null;
    final at = DateTime.tryParse(atRaw);
    if (at == null) return null;
    final status = UpdateCheckStatus.values
        .where((s) => s.name == statusRaw)
        .firstOrNull;
    // 枚举名不认识（版本降级/手改）就当没记录：显示一个错的结论比不显示更坏。
    if (status == null) return null;

    final code = json['latestCode'];
    final name = json['latestName'];
    return UpdateLastCheck(
      at: at,
      status: status,
      detail: json['detail'] is String ? json['detail'] as String : null,
      latestVersionCode: code is int ? code : null,
      latestVersionName: name is String ? name : null,
    );
  }
}

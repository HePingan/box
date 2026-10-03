import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_logger.dart';

/// ② 线路「最近取不到流」的本地记忆。
///
/// 背景（2026-10-02/03 实测）：部分采集线路拿到的是 `/share/<id>` 这类网页地址
/// （没有 `var main`），或者媒体域名 DNS/TCP 直接连不上 —— 现在只能**先失败一次**
/// 再自动换线，用户看到的是「点进去卡一下，然后被换到另一条线」。
///
/// 所以把「这条线最近取不到流」记下来，下一次进详情页时：
/// - 线路 chip 上直接标注（前置告知，不用等失败才知道）；
/// - 默认选线**跳过**它，除非所有线路都被标了（那说明是网络环境问题，不是线路问题）。
///
/// 记忆是按 **源 + 线路名** 聚合的（不是按单片）：同名线路在多数情况下走同一家
/// 采集/CDN，可用性相关性强，而且聚合起来才有统计意义。
/// 成功起播会立刻清掉标记 —— 线路恢复不用等 TTL 到期。
class LineReachabilityStore {
  LineReachabilityStore._();

  /// 失败标记的有效期：过期即视为「可以再试一次」，避免永久拉黑一条线路。
  static const Duration failureTtl = Duration(hours: 6);

  static const String _prefsKey = 'video_line_reachability_v1';

  static Map<String, LineReachabilityRecord> _cache = {};
  static bool _loaded = false;

  /// 仅测试用：清空内存缓存（不动磁盘）。
  static void resetForTest() {
    _cache = {};
    _loaded = false;
  }

  /// 线路指纹：源 + 线路名（大小写、首尾空白归一）。
  static String keyOf({required String sourceKey, required String lineName}) {
    final name = lineName.trim().toLowerCase();
    return '${sourceKey.trim()}|$name';
  }

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.trim().isEmpty) {
        _cache = {};
      } else {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _cache = {
            for (final entry in decoded.entries)
              if (entry.key is String && entry.value is Map)
                entry.key as String: LineReachabilityRecord.fromJson(
                  Map<String, dynamic>.from(entry.value as Map),
                ),
          };
        }
      }
    } catch (e) {
      // 记忆读不出来只影响「前置标注」，绝不能影响播放：当作没记忆。
      AppLogger.instance.log('lineReachability load failed: $e', tag: 'LINE');
      _cache = {};
    }
    _loaded = true;
  }

  /// 自检页用：当前全部线路记忆的只读快照（先 [ensureLoaded]）。
  static Map<String, LineReachabilityRecord> get records =>
      Map<String, LineReachabilityRecord>.unmodifiable(_cache);

  /// 自检页用：清空线路记忆。
  ///
  /// 场景：线路当时取不到流是网络环境问题（现在网络好了，标记还在），
  /// 用户想要一个"重新开始"的开关。清完 [_loaded] 保持 true，
  /// 免得下一次 ensureLoaded 又把刚清掉的从盘上读回来。
  static Future<void> clear() async {
    _cache = {};
    _loaded = true;
    await _persist();
    AppLogger.instance.log('lineReachability cleared by user', tag: 'LINE');
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          for (final entry in _cache.entries) entry.key: entry.value.toJson(),
        }),
      );
    } catch (e) {
      AppLogger.instance.log(
        'lineReachability persist failed: $e',
        tag: 'LINE',
      );
    }
  }

  /// 记一次「这条线取不到流」。
  static Future<void> markFailure({
    required String sourceKey,
    required String lineName,
    String? reason,
    DateTime? now,
  }) async {
    await ensureLoaded();
    final key = keyOf(sourceKey: sourceKey, lineName: lineName);
    final current = _cache[key] ?? const LineReachabilityRecord();
    _cache[key] = current.copyWith(
      failCount: current.failCount + 1,
      lastFailAt: now ?? DateTime.now(),
      lastReason: reason,
    );
    await _persist();
  }

  /// 记一次「这条线起播成功」：清掉标记，让恢复立刻生效。
  static Future<void> markSuccess({
    required String sourceKey,
    required String lineName,
    DateTime? now,
  }) async {
    await ensureLoaded();
    final key = keyOf(sourceKey: sourceKey, lineName: lineName);
    final current = _cache[key];
    // 没标记过的线路不必写盘（绝大多数线路属于这种，省掉无谓写入）。
    if (current == null || current.failCount == 0) return;
    _cache[key] = current.copyWith(
      failCount: 0,
      lastOkAt: now ?? DateTime.now(),
      lastReason: null,
    );
    await _persist();
  }

  /// 这条线是否「最近取不到流」（同步判定，界面直接读）。
  ///
  /// 判定只看：有失败记录、距最近一次失败没过期、且之后没有成功过。
  static bool isRecentlyUnreachable({
    required String sourceKey,
    required String lineName,
    DateTime? now,
    Duration? ttl,
  }) {
    final record = _cache[keyOf(sourceKey: sourceKey, lineName: lineName)];
    return record?.isRecentlyUnreachable(now: now, ttl: ttl) ?? false;
  }

  /// 给界面用的原因文案（拿不到就返回 null）。
  static String? failureReasonOf({
    required String sourceKey,
    required String lineName,
  }) {
    final record = _cache[keyOf(sourceKey: sourceKey, lineName: lineName)];
    if (record == null || record.failCount == 0) return null;
    return record.lastReason;
  }

  static LineReachabilityRecord? recordOf({
    required String sourceKey,
    required String lineName,
  }) {
    return _cache[keyOf(sourceKey: sourceKey, lineName: lineName)];
  }
}

/// 单条线路的取流记忆。
class LineReachabilityRecord {
  const LineReachabilityRecord({
    this.failCount = 0,
    this.lastFailAt,
    this.lastOkAt,
    this.lastReason,
  });

  final int failCount;
  final DateTime? lastFailAt;
  final DateTime? lastOkAt;
  final String? lastReason;

  /// 最近取不到流：有失败、没过期、且失败发生在最近一次成功之后。
  bool isRecentlyUnreachable({DateTime? now, Duration? ttl}) {
    if (failCount <= 0) return false;
    final failedAt = lastFailAt;
    if (failedAt == null) return false;
    final effectiveTtl = ttl ?? LineReachabilityStore.failureTtl;
    final reference = now ?? DateTime.now();
    if (reference.difference(failedAt) >= effectiveTtl) return false;
    final okAt = lastOkAt;
    if (okAt != null && okAt.isAfter(failedAt)) return false;
    return true;
  }

  LineReachabilityRecord copyWith({
    int? failCount,
    DateTime? lastFailAt,
    DateTime? lastOkAt,
    String? lastReason,
    bool clearReason = false,
  }) {
    return LineReachabilityRecord(
      failCount: failCount ?? this.failCount,
      lastFailAt: lastFailAt ?? this.lastFailAt,
      lastOkAt: lastOkAt ?? this.lastOkAt,
      lastReason: clearReason ? null : (lastReason ?? this.lastReason),
    );
  }

  Map<String, dynamic> toJson() => {
    'failCount': failCount,
    'lastFailAt': lastFailAt?.millisecondsSinceEpoch,
    'lastOkAt': lastOkAt?.millisecondsSinceEpoch,
    'lastReason': lastReason,
  };

  static LineReachabilityRecord fromJson(Map<String, dynamic> json) {
    DateTime? parse(Object? value) {
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return LineReachabilityRecord(
      failCount: json['failCount'] is int ? json['failCount'] as int : 0,
      lastFailAt: parse(json['lastFailAt']),
      lastOkAt: parse(json['lastOkAt']),
      lastReason: json['lastReason'] is String
          ? json['lastReason'] as String
          : null,
    );
  }
}

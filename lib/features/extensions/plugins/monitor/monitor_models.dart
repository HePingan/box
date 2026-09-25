// 服务监控插件（box 内置插件）：Kuma 快照的纯数据层。
//
// 数据来自 https://box.hpa888.top/monitors.json —— 由 175 上的
// /opt/kuma-monitor/gen_monitors_json.py 每 2 分钟采样 Kuma 后推送。
// 这里不依赖 dart:io / Flutter，解析规则的用例可以直接跑。

import 'dart:convert';
//
// 解析原则：**服务端怎么变都不许把整页搞崩**。
//   * 顶层结构不对（不是对象 / monitors 不是列表）→ 抛 MonitorFormatException，
//     调用方当作"这份快照不可用"，回退到上次成功的那份或报错。
//   * 单个条目缺字段/类型不对 → 尽量修（数字字符串、1/0 当 true/false），
//     连名字都没有就丢掉这一条，不影响其余条目。

/// 快照结构不对（整份不可用）。
class MonitorFormatException implements Exception {
  MonitorFormatException(this.message);

  final String message;

  @override
  String toString() => 'MonitorFormatException: $message';
}

class MonitorEntry {
  const MonitorEntry({
    required this.name,
    required this.up,
    this.id,
    this.pingMs,
    this.uptime24h,
    this.certDays,
    this.certValid,
    this.pingSeries = const <int?>[],
    this.upSeries = const <int>[],
    this.seriesStepSec = kDefaultSeriesStepSec,
  });

  final String name;
  final bool up;
  final int? id;
  final int? pingMs;
  final double? uptime24h;

  /// HTTPS 监控项的证书剩余天数（Kuma 的 `monitor_cert_days_remaining`）；
  /// 非 HTTPS 或服务端没采到就是 null。
  final int? certDays;

  /// 证书是否有效（`monitor_cert_is_valid`）；null = 不知道。
  final bool? certValid;

  /// 最近 N 次采样的延迟（毫秒）；`null` = 那一次没采到（**不是 0ms**）。
  final List<int?> pingSeries;

  /// 最近 N 次采样是否在线（1/0），与 [pingSeries] 等长。
  final List<int> upSeries;

  /// 相邻两次采样的间隔秒数（服务端给的，缺省 120）。
  final int seriesStepSec;

  /// 有没有可画的历史（至少两个点才画得出线）。
  bool get hasSeries => upSeries.length >= 2 || pingSeries.length >= 2;

  /// 折线用的点数（取两个序列里长的那个）。
  int get seriesLength =>
      pingSeries.length > upSeries.length ? pingSeries.length : upSeries.length;

  /// 序列里最后一次在线之后连续不通了几次采样；一直在线返回 0。
  ///
  /// 只在**有序列**时可用；没有序列（老快照）返回 0，界面就别下结论。
  int get consecutiveDownSamples {
    if (upSeries.isEmpty) return 0;
    var count = 0;
    for (var i = upSeries.length - 1; i >= 0; i--) {
      if (upSeries[i] == 1) break;
      count += 1;
    }
    return count;
  }

  /// "从多久前开始不通"的文案；在线或没有序列时返回 null。
  String? get downSinceLabel {
    final samples = consecutiveDownSamples;
    if (samples <= 0) return null;
    final minutes = (samples * seriesStepSec) ~/ 60;
    if (minutes <= 0) return '刚开始不通（不到 1 分钟）';
    if (minutes < 60) return '已不通约 $minutes 分钟';
    final hours = minutes ~/ 60;
    if (hours < 24) return '已不通约 $hours 小时';
    return '已不通超过 1 天';
  }

  /// 证书一行文案：没有证书信息返回 null，界面就不显示这一段。
  String? get certificateLabel {
    if (certValid == false) return '证书已失效';
    final days = certDays;
    if (days == null) return null;
    if (days <= 0) return '证书已到期';
    return '证书 $days 天';
  }

  /// 证书是否该被提醒（失效/已到期/不足 30 天）。没有证书信息的项永远不提醒。
  bool get certificateWarning {
    if (certValid == false) return true;
    final days = certDays;
    if (days == null) return false;
    return days < 30;
  }

  /// 站点标识：优先用服务端 id，没有就用名字（名字在 Kuma 里是人写的，够稳定）。
  String get key => id != null ? 'id:$id' : 'name:$name';

  /// 从一条记录里尽力取值；名字缺失返回 null（调用方丢掉这条）。
  static MonitorEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = _asString(raw['name'])?.trim();
    if (name == null || name.isEmpty) return null;
    return MonitorEntry(
      name: name,
      up: _asBool(raw['up']) ?? false,
      id: _asInt(raw['id']),
      pingMs: _asInt(raw['pingMs']),
      uptime24h: _asDouble(raw['uptime24h']),
      certDays: _asInt(raw['certDays']),
      certValid: _asBool(raw['certValid']),
      pingSeries: _asPingSeries(raw['seriesPing']),
      upSeries: _asUpSeries(raw['seriesUp']),
      seriesStepSec: _asPositiveInt(raw['seriesStepSec']) ?? kDefaultSeriesStepSec,
    );
  }
}

/// 服务端没给采样间隔时的默认值（cron 每 2 分钟一次）。
const int kDefaultSeriesStepSec = 120;

/// 延迟序列：只认数字与 null（**别的类型一律丢掉，不能当 0**）。
List<int?> _asPingSeries(Object? raw) {
  if (raw is! List) return const <int?>[];
  final out = <int?>[];
  for (final item in raw) {
    if (item == null) {
      out.add(null);
    } else if (item is int) {
      out.add(item);
    } else if (item is double && item.isFinite) {
      out.add(item.round());
    }
    // 字符串/布尔等一律跳过：宁少一点，不能画错。
  }
  return out;
}

/// 在线序列：非 1 一律当 0（"不确定"在图上不该显成在线）。
List<int> _asUpSeries(Object? raw) {
  if (raw is! List) return const <int>[];
  return <int>[for (final item in raw) item == 1 ? 1 : 0];
}

/// 严格只认数字（**字符串不采信**）：服务端自己的字段没必要宽容解析，
/// 而"把 '60' 当 60 用"这种宽容一旦出错很难发现。
int? _asPositiveInt(Object? raw) {
  final int v;
  if (raw is int) {
    v = raw;
  } else if (raw is double && raw.isFinite) {
    v = raw.round();
  } else {
    return null;
  }
  return v <= 0 ? null : v;
}

class MonitorSnapshot {
  const MonitorSnapshot({
    required this.monitors,
    required this.generatedAt,
    this.panelUrl,
  });

  final List<MonitorEntry> monitors;

  /// 服务端采样时刻；解析不出来就是 null（界面显示"时间未知"）。
  final DateTime? generatedAt;
  final String? panelUrl;

  int get total => monitors.length;
  int get upCount => monitors.where((m) => m.up).length;
  int get downCount => total - upCount;
  bool get allUp => total > 0 && downCount == 0;

  /// 解析失败（结构不对）抛 [MonitorFormatException]。
  factory MonitorSnapshot.fromJson(Object? raw) {
    if (raw is! Map) {
      throw MonitorFormatException('顶层不是对象');
    }
    final list = raw['monitors'];
    if (list is! List) {
      throw MonitorFormatException('monitors 不是列表');
    }
    final monitors = <MonitorEntry>[];
    for (final item in list) {
      final entry = MonitorEntry.tryParse(item);
      if (entry != null) monitors.add(entry);
    }
    return MonitorSnapshot(
      monitors: monitors,
      generatedAt: _asDateTime(raw['generatedAt']),
      panelUrl: _asString(raw['panelUrl']),
    );
  }

  /// 从已落盘的字符串恢复（缓存路径）；同样可能抛 [MonitorFormatException]。
  factory MonitorSnapshot.parse(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw MonitorFormatException('不是合法 JSON');
    }
    return MonitorSnapshot.fromJson(decoded);
  }
}

/// 「多久之前」的人话。未知时间返回 null，让调用方自己决定说什么。
String? monitorAgeText(DateTime? generatedAt, {DateTime? now}) {
  if (generatedAt == null) return null;
  final delta = (now ?? DateTime.now()).difference(generatedAt.toLocal());
  if (delta.isNegative || delta.inSeconds < 60) return '刚刚';
  if (delta.inMinutes < 60) return '${delta.inMinutes} 分钟前';
  if (delta.inHours < 24) return '${delta.inHours} 小时前';
  return '${delta.inDays} 天前';
}

/// 快照"太旧"的阈值（287 D4）。
///
/// 采样链是 cron 每 2 分钟一次，所以 10 分钟 = **连续 5 次没动静**才提醒：
/// 偶发抖动不当故障，真断了也不会静默 —— 静态快照最大的风险就是没人发现它不再更新。
const Duration kSnapshotStaleAfter = Duration(minutes: 10);

/// 快照是否已经陈旧到"采样可能断了"。
///
/// 时间未知（null）时**不下结论**返回 false：界面在那里另有"时间未知"要说，
/// 不能把"不知道"显示成"断了"。
bool isMonitorSnapshotStale(
  DateTime? generatedAt, {
  DateTime? now,
  Duration staleAfter = kSnapshotStaleAfter,
}) {
  if (generatedAt == null) return false;
  final delta = (now ?? DateTime.now()).difference(generatedAt.toLocal());
  return delta > staleAfter;
}

String monitorPingText(int? pingMs) => pingMs == null ? '—' : '$pingMs ms';

/// 可用率文案：保留两位以内的小数，整数不写小数点（100% 而不是 100.00%）。
String monitorUptimeText(double? ratio) {
  if (ratio == null) return '—';
  final v = ratio.clamp(0, 100).toDouble();
  if ((v - v.roundToDouble()).abs() < 0.005) return '${v.round()}%';
  return '${v.toStringAsFixed(2)}%';
}

// ── 宽容取值助手 ────────────────────────────────────────────────

String? _asString(Object? v) => v is String ? v : (v == null ? null : '$v');

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

double? _asDouble(Object? v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

bool? _asBool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'up' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'down' || s == 'no') return false;
  }
  return null;
}

DateTime? _asDateTime(Object? v) {
  if (v is! String || v.trim().isEmpty) return null;
  return DateTime.tryParse(v.trim());
}

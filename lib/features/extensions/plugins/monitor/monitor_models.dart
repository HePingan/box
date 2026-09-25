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
    );
  }
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

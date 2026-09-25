// 服务器运维插件（box 内置插件）：主机指标快照的纯数据层。
//
// 数据来自 https://box.hpa888.top/hosts.json —— 由 175 上的 cron 每 2 分钟采样
// 各主机后产出的静态文件（与 monitors.json 同一条链路）。
// 这里不依赖 dart:io / Flutter，解析规则的用例可以直接跑。
//
// 解析原则：**服务端怎么变都不许把整页搞崩**。
//   * 顶层结构不对（不是对象 / hosts 不是列表）→ 抛 HostFormatException，
//     调用方当作"这份快照不可用"，回退到上次成功的那份或报错。
//   * 单个条目缺字段 → 尽量修（字符串数字、用 used/total 反算百分比）；
//     **离线的机器只有 id/name/ip + online:false，其余字段全缺**——这是常态，
//     不是异常：它必须显示成"离线"，而不是崩，也不是显示成 0%。
//   * 连名字都没有就丢掉这一条，不影响其余条目。

import 'dart:convert';

/// 快照结构不对（整份不可用）。
class HostFormatException implements Exception {
  HostFormatException(this.message);

  final String message;

  @override
  String toString() => 'HostFormatException: $message';
}

/// 采样间隔：数据源是 175 的 cron 每 2 分钟产出一次静态文件，
/// 所以"历史点之间差 2 分钟"是**服务端的节拍**，不是本地猜的。
const int kHostSampleStepSec = 120;

/// 每台机器每项指标保留的点数（约 2 小时）。再多也没人看得清，
/// 而且 SharedPreferences 里存的是逐台 JSON，得有个上限兜住体积。
const int kHostHistoryMaxPoints = 60;

class HostEntry {
  const HostEntry({
    required this.id,
    required this.name,
    this.ip,
    this.online = false,
    this.cpuPercent,
    this.cpuCount,
    this.memTotalBytes,
    this.memUsedBytes,
    this.memPercent,
    this.swapTotalBytes,
    this.swapUsedBytes,
    this.diskTotalBytes,
    this.diskUsedBytes,
    this.diskPercent,
    this.load1,
    this.load5,
    this.load15,
    this.uptimeSeconds,
    this.netRxBytesPerSec,
    this.netTxBytesPerSec,
  });

  /// 机器标识：服务端 id 缺失时退化成名字（名字在 hosts.json 里是人写的，够稳定）。
  final String id;
  final String name;
  final String? ip;
  final bool online;

  final double? cpuPercent;
  final int? cpuCount;

  final int? memTotalBytes;
  final int? memUsedBytes;
  final double? memPercent;
  final int? swapTotalBytes;
  final int? swapUsedBytes;

  final int? diskTotalBytes;
  final int? diskUsedBytes;
  final double? diskPercent;

  final double? load1;
  final double? load5;
  final double? load15;

  final int? uptimeSeconds;
  final int? netRxBytesPerSec;
  final int? netTxBytesPerSec;

  /// 从一条记录里尽力取值；**名字缺失返回 null（调用方丢掉这条）**。
  ///
  /// 离线机器缺的字段全部保持 null —— 界面据此显示"离线"，
  /// 而不是把 null 兜成 0 再画成一条贴着底的线。
  static HostEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = _asString(raw['name'])?.trim();
    if (name == null || name.isEmpty) return null;
    final idRaw = _asString(raw['id'])?.trim();
    final id = (idRaw == null || idRaw.isEmpty) ? name : idRaw;

    final memTotal = _asInt(raw['memTotalBytes']);
    final memUsed = _asInt(raw['memUsedBytes']);
    final diskTotal = _asInt(raw['diskTotalBytes']);
    final diskUsed = _asInt(raw['diskUsedBytes']);

    return HostEntry(
      id: id,
      name: name,
      ip: _asString(raw['ip'])?.trim(),
      online: _asBool(raw['online']) ?? false,
      cpuPercent: _percent(raw['cpuPercent']),
      cpuCount: _asInt(raw['cpuCount']),
      memTotalBytes: memTotal,
      memUsedBytes: memUsed,
      memPercent: _percent(raw['memPercent'], used: memUsed, total: memTotal),
      swapTotalBytes: _asInt(raw['swapTotalBytes']),
      swapUsedBytes: _asInt(raw['swapUsedBytes']),
      diskTotalBytes: diskTotal,
      diskUsedBytes: diskUsed,
      diskPercent: _percent(raw['diskPercent'], used: diskUsed, total: diskTotal),
      load1: _asDouble(raw['load1']),
      load5: _asDouble(raw['load5']),
      load15: _asDouble(raw['load15']),
      uptimeSeconds: _asInt(raw['uptimeSeconds']),
      netRxBytesPerSec: _asInt(raw['netRxBytesPerSec']),
      netTxBytesPerSec: _asInt(raw['netTxBytesPerSec']),
    );
  }
}

class HostSnapshot {
  const HostSnapshot({required this.hosts, this.generatedAt});

  final List<HostEntry> hosts;

  /// 服务端采样时刻；解析不出来就是 null（界面显示"时间未知"）。
  final DateTime? generatedAt;

  int get total => hosts.length;
  int get onlineCount => hosts.where((h) => h.online).length;
  int get offlineCount => total - onlineCount;
  bool get allOnline => total > 0 && offlineCount == 0;

  bool get isEmpty => hosts.isEmpty;

  /// 解析失败（结构不对）抛 [HostFormatException]。
  factory HostSnapshot.fromJson(Object? raw) {
    if (raw is! Map) {
      throw HostFormatException('顶层不是对象');
    }
    final list = raw['hosts'];
    if (list is! List) {
      throw HostFormatException('hosts 不是列表');
    }
    final hosts = <HostEntry>[];
    for (final item in list) {
      final entry = HostEntry.tryParse(item);
      if (entry != null) hosts.add(entry);
    }
    return HostSnapshot(
      hosts: hosts,
      generatedAt: _asDateTime(raw['generatedAt']),
    );
  }

  /// 从已落盘的字符串恢复（缓存路径）；同样可能抛 [HostFormatException]。
  factory HostSnapshot.parse(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw HostFormatException('不是合法 JSON');
    }
    return HostSnapshot.fromJson(decoded);
  }
}

/// 一台机器三项指标的历史（环形缓冲，只存数字）。
///
/// 为什么只存数字、不存时间戳：采样间隔是服务端固定的 2 分钟
/// （见 [kHostSampleStepSec]），时间轴能推算出来；而把整份快照或每条带
/// 时间戳存进去，体积会随点数线性膨胀，还会把"服务端字段变来变去"的
/// 兼容问题带进缓存——缓存只需要回答"这条线长什么样"。
class HostHistory {
  const HostHistory({
    this.cpu = const <double>[],
    this.mem = const <double>[],
    this.disk = const <double>[],
  });

  final List<double> cpu;
  final List<double> mem;
  final List<double> disk;

  /// 有没有可画的历史（至少两个点才画得出线）。
  bool get hasAny => cpu.length >= 2 || mem.length >= 2 || disk.length >= 2;

  /// 追加一次采样（值为 null 的那一项**不落点**：缺字段不是 0）。
  /// 超过 [maxPoints] 时丢最旧的（环形缓冲）。
  HostHistory appended({
    double? cpu,
    double? mem,
    double? disk,
    int maxPoints = kHostHistoryMaxPoints,
  }) {
    return HostHistory(
      cpu: cpu == null ? this.cpu : pushHostRing(this.cpu, cpu, maxPoints),
      mem: mem == null ? this.mem : pushHostRing(this.mem, mem, maxPoints),
      disk: disk == null ? this.disk : pushHostRing(this.disk, disk, maxPoints),
    );
  }

  String encode() => jsonEncode(<String, Object?>{
        'cpu': cpu,
        'mem': mem,
        'disk': disk,
      });

  /// 从缓存字符串恢复；坏了就当"没有历史"（缓存永远是锦上添花，不能拦住页面）。
  static HostHistory decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const HostHistory();
      return HostHistory(
        cpu: _numberList(decoded['cpu']),
        mem: _numberList(decoded['mem']),
        disk: _numberList(decoded['disk']),
      );
    } catch (_) {
      return const HostHistory();
    }
  }
}

/// 往环形缓冲里追加一个值，超出 [maxPoints] 就丢最旧的。
List<double> pushHostRing(List<double> source, double value, int maxPoints) {
  final next = <double>[...source, value];
  if (next.length <= maxPoints) return List<double>.unmodifiable(next);
  return List<double>.unmodifiable(next.sublist(next.length - maxPoints));
}

// ── 文案（界面只调这些，别在 widget 里拼字符串） ──────────────────

/// 「多久之前」的人话。未知时间返回 null，让调用方自己决定说什么。
String? hostAgeText(DateTime? at, {DateTime? now}) {
  if (at == null) return null;
  final delta = (now ?? DateTime.now()).difference(at.toLocal());
  if (delta.isNegative || delta.inSeconds < 60) return '刚刚';
  if (delta.inMinutes < 60) return '${delta.inMinutes} 分钟前';
  if (delta.inHours < 24) return '${delta.inHours} 小时前';
  return '${delta.inDays} 天前';
}

/// 百分比文案：保留一位小数，整数不写小数点（55% 而不是 55.0%）。
String hostPercentText(double? percent) {
  if (percent == null) return '—';
  final v = percent.clamp(0, 100).toDouble();
  if ((v - v.roundToDouble()).abs() < 0.05) return '${v.round()}%';
  return '${v.toStringAsFixed(1)}%';
}

/// 字节数文案（1024 进制，一位小数）。null（离线机器没采到）显示 `—`。
String hostBytesText(int? bytes) {
  if (bytes == null || bytes < 0) return '—';
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  if (unit == 0) return '$bytes ${units[unit]}';
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}

/// 速率文案（字节/秒）；负数按 0 处理。
String hostRateText(int? bytesPerSec) {
  if (bytesPerSec == null) return '—';
  return '${hostBytesText(bytesPerSec < 0 ? 0 : bytesPerSec)}/s';
}

/// 负载文案：三个值拼一行，缺的用 `—` 顶位（不留空洞让用户以为漏读）。
String hostLoadText(double? one, double? five, double? fifteen) {
  String fmt(double? v) => v == null ? '—' : v.toStringAsFixed(2);
  return '${fmt(one)} / ${fmt(five)} / ${fmt(fifteen)}';
}

/// 运行时长文案；null 显示 `—`。
String hostUptimeText(int? seconds) {
  if (seconds == null || seconds < 0) return '—';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (days > 0) return '$days 天 $hours 小时';
  if (hours > 0) return '$hours 小时 $minutes 分钟';
  return '$minutes 分钟';
}

/// 内存/磁盘一行的文案：`已用 / 总量（百分比）`。
String hostUsageText(int? used, int? total, double? percent) {
  final percentText = hostPercentText(percent);
  if (used == null || total == null) {
    // 缺一侧就只给百分比（或都缺时给 —），别硬凑一个"0 B / 0 B"。
    return percentText == '—' ? '—' : percentText;
  }
  return '${hostBytesText(used)} / ${hostBytesText(total)}（$percentText）';
}

// ── 宽容取值助手 ────────────────────────────────────────────────

/// 百分比：优先用服务端给的值；缺了就用 used/total 反算（"尽量修"）。
/// 两个都没有才是 null —— 界面据此显示 `—`，不是 0%。
double? _percent(Object? raw, {int? used, int? total}) {
  final direct = _asDouble(raw);
  if (direct != null) return direct.clamp(0, 100).toDouble();
  if (used != null && total != null && total > 0) {
    return (used / total * 100).clamp(0, 100).toDouble();
  }
  return null;
}

String? _asString(Object? v) => v is String ? v : (v == null ? null : '$v');

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is double) return v.isFinite ? v.round() : null;
  if (v is String) return int.tryParse(v.trim());
  return null;
}

double? _asDouble(Object? v) {
  if (v is double) return v.isFinite ? v : null;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

bool? _asBool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'online' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'offline' || s == 'no') return false;
  }
  return null;
}

DateTime? _asDateTime(Object? v) {
  if (v is! String || v.trim().isEmpty) return null;
  return DateTime.tryParse(v.trim());
}

/// 只认数字（字符串一律丢掉）：缓存里的序列是我们自己写的，
/// 出现字符串说明缓存被别的东西占了，宁可当成"没有历史"。
List<double> _numberList(Object? raw) {
  if (raw is! List) return const <double>[];
  final out = <double>[];
  for (final item in raw) {
    if (item is num && item.isFinite) {
      out.add(item.toDouble());
    }
  }
  return List<double>.unmodifiable(out);
}

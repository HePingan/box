// 被监控站点的快照（`monitors.json`）——体检卡的数据源。
//
// 这份快照是 175 每 2 分钟采 Uptime Kuma 得来的，里面**已经有 certDays**（每个站点
// 的证书剩余天数），所以体检卡不用自己去翻证书文件：数据早就在，缺的只是"摆到手机上"。
//
// 解析原则与 hosts.json 一样：**服务端怎么变都不许把整页搞崩** —— 单个站点解析
// 不出来就跳过它，不因为一条脏数据让整张卡空掉。

/// 一个被监控的站点。
class MonitorEntry {
  const MonitorEntry({
    required this.name,
    required this.up,
    this.certDays,
    this.pingMs,
    this.url,
  });

  final String name;
  final bool up;

  /// 证书剩余天数；HTTP 检查（非 HTTPS）的监控没有这个值 → null（**不是 0**）。
  final int? certDays;
  final int? pingMs;
  final String? url;

  /// 证书该留意了（阈值与巡检脚本一致：30 天提醒、14 天算急）。
  bool get certTight => certDays != null && certDays! <= 30;
  bool get certUrgent => certDays != null && certDays! <= 14;

  static MonitorEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final days = raw['certDays'];
    final ping = raw['pingMs'];
    final url = raw['url'];
    return MonitorEntry(
      name: name.trim(),
      up: raw['up'] == true,
      certDays: days is num ? days.toInt() : null,
      pingMs: ping is num ? ping.toInt() : null,
      url: url is String && url.trim().isNotEmpty ? url.trim() : null,
    );
  }
}

/// 一份监控快照。
class MonitorSnapshot {
  const MonitorSnapshot({this.monitors = const <MonitorEntry>[], this.generatedAt});

  final List<MonitorEntry> monitors;
  final DateTime? generatedAt;

  int get total => monitors.length;
  int get upCount => monitors.where((m) => m.up).length;
  bool get allUp => total > 0 && upCount == total;
  List<String> get downNames =>
      [for (final m in monitors) if (!m.up) m.name];

  /// 证书最快到期的几张（升序，只含拿得到天数的）。
  ///
  /// 排序按天数而不是按名字：卡片的目的就是"哪张最先到期"。
  List<MonitorEntry> nearestCerts({int limit = 3}) {
    final withDays = [
      for (final m in monitors)
        if (m.certDays != null) m,
    ]..sort((a, b) => a.certDays!.compareTo(b.certDays!));
    return withDays.length <= limit ? withDays : withDays.sublist(0, limit);
  }

  static MonitorSnapshot? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final list = raw['monitors'];
    if (list is! List) return null;
    final monitors = <MonitorEntry>[];
    for (final item in list) {
      final entry = MonitorEntry.tryParse(item);
      if (entry != null) monitors.add(entry);
    }
    return MonitorSnapshot(
      monitors: monitors,
      generatedAt: _asDate(raw['generatedAt']),
    );
  }

  static DateTime? _asDate(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;
}

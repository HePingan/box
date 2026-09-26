// 服务端存的主机历史（`hosts.json` 里的 `series`）。
//
// 手机本地也攒一份（十来点），但那份只活在"你打开过 App 的那段时间"里 —— 看不出
// "昨晚三点开始飙的"。服务端这份每 2 分钟一点、留 24 小时（720 点），翻昨天的账靠它。

/// 一台机器的一段时间序列。
///
/// **值为 null 表示那一刻没采到**（机器离线），不是 0：画线时把 null 丢掉，
/// 而不是塞 0 —— 塞 0 会把"没采到"画成"CPU 0%，很闲"，跟事实相反。
class HostSeries {
  const HostSeries({
    this.t = const <int>[],
    this.cpu = const <double?>[],
    this.mem = const <double?>[],
    this.disk = const <double?>[],
    this.load = const <double?>[],
  });

  final List<int> t;
  final List<double?> cpu;
  final List<double?> mem;
  final List<double?> disk;
  final List<double?> load;

  /// 解析一台机器的序列；结构不对就返回 null（界面退回本机记录，不报错）。
  static HostSeries? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final t = _ints(raw['t']);
    if (t.isEmpty) return null;
    return HostSeries(
      t: t,
      cpu: _doubles(raw['cpu']),
      mem: _doubles(raw['mem']),
      disk: _doubles(raw['disk']),
      load: _doubles(raw['load']),
    );
  }

  static List<int> _ints(Object? raw) => raw is List
      ? [
          for (final v in raw)
            if (v is num) v.toInt(),
        ]
      : const <int>[];

  static List<double?> _doubles(Object? raw) => raw is List
      ? [
          for (final v in raw) v is num ? v.toDouble() : null,
        ]
      : const <double?>[];

  bool get isEmpty => t.length < 2;
  bool get hasAny => !isEmpty && (cpu.length >= 2 || mem.length >= 2 || disk.length >= 2);

  /// 取最近 [d] 的一段。
  ///
  /// 时间基准取**序列自己最后一个点**，不取手机时钟：手机时区/时钟偏了不该让曲线
  /// 整段空掉；而且这样"最后一格"永远是当前。
  ///
  /// 边界是**含**的：窗口起点上的那个点算在内（每 2 分钟一点时，"最近 1 小时"
  /// 会拿到 31 个点）。上限那条走的是"比全段还长 → 原样返回"。
  HostSeries window(Duration d) {
    if (t.isEmpty) return this;
    final end = t.last;
    final from = end - d.inSeconds;
    final i = t.indexWhere((x) => x >= from);
    final start = i < 0 ? t.length - 1 : i;
    List<T> tail<T>(List<T> src) => start == 0 ? src : src.sublist(start.clamp(0, src.length));
    return HostSeries(
      t: tail(t),
      cpu: tail(cpu),
      mem: tail(mem),
      disk: tail(disk),
      load: tail(load),
    );
  }

  /// 画线用：丢掉没采到的点（折线画不出"断点"，丢掉比塞 0 诚实）。
  static List<double> points(List<double?> values) =>
      [for (final v in values) ?v];
}

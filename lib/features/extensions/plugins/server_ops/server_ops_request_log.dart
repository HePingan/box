// 服务器运维插件：最近请求元数据（A9）。
//
// 为什么要有：真机出问题时，用户发来的截图里只有一句报错 —— 哪台机器、哪个入口、
// 什么状态码、耗时多少，全都没有。289 列的三条"必须真机确认"（终端辅助键、多选上传手感、
// 目录复制往返）就是这样一轮轮顺延下来的。把最后一次请求的元数据留在面板上，
// 截图就自带证据，不用再问"你当时填的是哪台"。
//
// **硬约定：只记 入口 / 机器 / 行不行 / 人话结论 / 耗时 / 时间。**
// 不记口令、不记请求头、不记响应体。口令在这个面板上出现一次就等于泄露一次
// （面板会被截图、会被共享屏幕），所以这条有专门的回归用例守着。

/// 一条请求的元数据。[detail] 是人话结论（成功文案或错误文案），不含任何凭据。
class OpsRequestRecord {
  const OpsRequestRecord({
    required this.entry,
    required this.serverId,
    required this.serverLabel,
    required this.ok,
    required this.detail,
    required this.duration,
    required this.at,
  });

  /// 入口：文件 / 终端 / 快照 / 体检。
  final String entry;

  /// 哪台机器（多服务器时代的关键信息：同一句报错，哪台机器差别很大）。
  final String serverId;

  /// 机器显示名（给面板直接渲染用；机器被删掉后旧记录仍可读）。
  final String serverLabel;

  final bool ok;

  /// 人话结论，例如 `已下载 日志.txt` / `认证失败（401）…` / `超时`。
  final String detail;

  final Duration duration;
  final DateTime at;

  /// 面板与日志里的一行（不含凭据）。
  String get summary => '$entry · $serverLabel · ${ok ? 'OK' : '失败'} · '
      '${duration.inMilliseconds} ms · $detail';
}

/// 环形缓冲：只留最近 [capacity] 条，新的在前。
///
/// 抽成独立类（而不是页面里的字段）有两个原因：纯 Dart 可单测；体检面板与各页签
/// 都能往同一条流里记，不必各自维护。
class OpsRequestLog {
  OpsRequestLog({this.capacity = 20}) : assert(capacity > 0);

  final int capacity;
  final List<OpsRequestRecord> _items = <OpsRequestRecord>[];

  /// 最近若干条，新的在前。
  List<OpsRequestRecord> get items =>
      List<OpsRequestRecord>.unmodifiable(_items.reversed);

  int get length => _items.length;

  void record(OpsRequestRecord rec) {
    _items.add(rec);
    if (_items.length > capacity) {
      _items.removeRange(0, _items.length - capacity);
    }
  }

  /// 记一次调用：自己计时，异常也记（失败记录才是最有用的那半）。
  Future<T> time<T>(
    Future<T> Function() body, {
    required String entry,
    required String serverId,
    required String serverLabel,
    String Function(Object error)? describeError,
    String? okDetail,
  }) async {
    final started = DateTime.now();
    try {
      final value = await body();
      record(OpsRequestRecord(
        entry: entry,
        serverId: serverId,
        serverLabel: serverLabel,
        ok: true,
        detail: okDetail ?? '完成',
        duration: DateTime.now().difference(started),
        at: started,
      ));
      return value;
    } catch (e) {
      record(OpsRequestRecord(
        entry: entry,
        serverId: serverId,
        serverLabel: serverLabel,
        ok: false,
        detail: describeError?.call(e) ?? e.toString(),
        duration: DateTime.now().difference(started),
        at: started,
      ));
      rethrow;
    }
  }

  void clear() => _items.clear();
}

/// 进程内共享的那一条（页面、页签、体检都往这里记）。
OpsRequestLog serverOpsRequestLog = OpsRequestLog();

/// 单测接缝：换掉共享实例，跑完记得 `debugSetOpsRequestLog()` 复位。
void debugSetOpsRequestLog([OpsRequestLog? log]) {
  serverOpsRequestLog = log ?? OpsRequestLog();
}

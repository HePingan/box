// 传输限速：把"平均速率"作为约束，而不是每块都睡固定时长。
//
// 做法是**追平时间账**：按速率算出"已传这么多字节本该花多久"，与真实已用时间比，
// 差多少就补等多少。好处是：
//   * 服务器/磁盘偶尔快一阵不会被额外惩罚（欠账还清后自然不再等）；
//   * 速率与本地读写速度无关，弱网、Wi-Fi 下的表现一致；
//   * 判定是**纯函数**（[lag]），单测不需要真等时间。
//
// 0 或负数 = 不限速（调用方直接不建这个对象）。

class TransferThrottle {
  TransferThrottle(this.bytesPerSecond, {Future<void> Function(Duration)? wait})
      : assert(bytesPerSecond > 0, '限速必须为正；不限速就不该建实例'),
        _wait = wait ?? ((d) => Future<void>.delayed(d));

  /// 目标速率（字节/秒）。
  final int bytesPerSecond;

  final Future<void> Function(Duration) _wait;

  /// 已传 [receivedBytes]、已用 [elapsed] 时，还要补等多久才不超过目标速率。
  ///
  /// 超前（欠账还清）返回 [Duration.zero]，不返回负值 —— 负延迟没有意义，
  /// 而且让调用方少一个分支。
  Duration lag(int receivedBytes, Duration elapsed) {
    if (receivedBytes <= 0 || bytesPerSecond <= 0) return Duration.zero;
    final targetMicros =
        (receivedBytes * Duration.microsecondsPerSecond) ~/ bytesPerSecond;
    final diff = targetMicros - elapsed.inMicroseconds;
    return diff <= 0 ? Duration.zero : Duration(microseconds: diff);
  }

  /// 传完一块后调用：必要时等一等。
  Future<void> limit(int receivedBytes, Duration elapsed) async {
    final d = lag(receivedBytes, elapsed);
    if (d > Duration.zero) await _wait(d);
  }
}

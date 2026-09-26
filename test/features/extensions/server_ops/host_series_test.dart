// 服务端主机历史的纯逻辑用例。
//
// 守两条：**null 不是 0**（没采到 ≠ 机器很闲），以及窗口切得对（时间基准取序列
// 自己最后一个点，不取手机时钟 —— 手机时区偏了不该整段空掉）。

import 'package:box/features/extensions/plugins/server_ops/host_series.dart';
import 'package:flutter_test/flutter_test.dart';

HostSeries _series() => const HostSeries(
      // 每 120 秒一点，共 5 点（0、120、240、360、480）
      t: [1000, 1120, 1240, 1360, 1480],
      cpu: [10, null, 30, 40, 50],
      mem: [20, 25, 30, 35, 40],
      disk: [60, 60, 60, 61, 61],
      load: [0.5, null, null, 0.9, 1.0],
    );

void main() {
  test('解析：结构不对就返回 null（界面退回本机记录，不报错）', () {
    expect(HostSeries.tryParse(null), isNull);
    expect(HostSeries.tryParse('nope'), isNull);
    expect(HostSeries.tryParse({'t': 'x'}), isNull);
    expect(HostSeries.tryParse({'t': <int>[]}), isNull);
    expect(HostSeries.tryParse({'t': const [1, 2], 'cpu': const [1, 2]}), isNotNull);
  });

  test('解析：值里的 null 保留（没采到 ≠ 0）', () {
    final s = HostSeries.tryParse({
      't': const [1, 2, 3],
      'cpu': const [10, null, 30],
    })!;
    expect(s.cpu, const [10, null, 30]);
  });

  test('画线时丢掉没采到的点（折线画不出断点，塞 0 更糟）', () {
    expect(HostSeries.points([10, null, 30]), const [10.0, 30.0]);
    expect(HostSeries.points(const [null, null]), isEmpty);
  });

  test('窗口：边界是含的（每 120 秒一点时，最近 2 分钟 = 末尾两个点）', () {
    final w = _series().window(const Duration(minutes: 2));
    expect(w.t, const [1360, 1480]);
    expect(w.cpu, const [40, 50]);
  });

  test('窗口：比一个采样间隔还短 → 只剩最后一点（不是空）', () {
    final w = _series().window(const Duration(minutes: 1));
    expect(w.t, const [1480]);
    expect(w.cpu, const [50]);
  });

  test('窗口：取最近 4 分钟 → 后 3 点', () {
    final w = _series().window(const Duration(minutes: 4));
    expect(w.t, const [1240, 1360, 1480]);
  });

  test('窗口：比全段还长 → 原样（不越界、不返回空）', () {
    final w = _series().window(const Duration(hours: 24));
    expect(w.t.length, 5);
    expect(w.cpu.length, 5);
  });

  test('空序列不炸', () {
    const empty = HostSeries();
    expect(empty.isEmpty, isTrue);
    expect(empty.hasAny, isFalse);
    expect(empty.window(const Duration(hours: 1)).t, isEmpty);
  });
}

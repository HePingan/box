// 监控历史序列（287 P3）：解析容忍度 + "从什么时候开始不通"的纯逻辑。
//
// 立场：**宁可少画一段线，也不能画错** —— 没采到的点必须是 null（不是 0ms），
// 不认识的类型一律丢。
import 'package:box/features/extensions/plugins/monitor/monitor_models.dart';
import 'package:flutter_test/flutter_test.dart';

MonitorEntry _entry({
  List<Object?>? ping,
  List<Object?>? up,
  Object? step,
  bool isUp = true,
}) =>
    MonitorEntry.tryParse(<String, Object?>{
      'name': 'x',
      'up': isUp,
      'seriesPing': ping,
      'seriesUp': up,
      'seriesStepSec': step,
    })!;

void main() {
  group('序列解析', () {
    test('数字保留、null 保留（不能当 0）', () {
      final e = _entry(ping: <Object?>[10, null, 30], up: <Object?>[1, 0, 1]);
      expect(e.pingSeries, <int?>[10, null, 30]);
      expect(e.upSeries, <int>[1, 0, 1]);
    });

    test('不认识的类型丢掉：字符串/布尔不当数字', () {
      final e = _entry(ping: <Object?>[10, '20', true, 30.6], up: <Object?>[1, 'x', 0]);
      expect(e.pingSeries, <int?>[10, 31], reason: '字符串与布尔丢掉，double 取整');
      // 在线序列**保持与采样次数一一对应**（长度不能缩），非 1 一律当 0。
      expect(e.upSeries, <int>[1, 0, 0]);
    });

    test('没有序列字段 → 空序列、默认步长', () {
      final e = MonitorEntry.tryParse(<String, Object?>{'name': 'x', 'up': true})!;
      expect(e.pingSeries, isEmpty);
      expect(e.upSeries, isEmpty);
      expect(e.seriesStepSec, kDefaultSeriesStepSec);
      expect(e.hasSeries, isFalse);
    });

    test('坏步长回默认（0/负数/字符串都不采信）', () {
      expect(_entry(step: 0).seriesStepSec, kDefaultSeriesStepSec);
      expect(_entry(step: -5).seriesStepSec, kDefaultSeriesStepSec);
      expect(_entry(step: '60').seriesStepSec, kDefaultSeriesStepSec);
      expect(_entry(step: 60).seriesStepSec, 60);
    });

    test('只有一个点也算"没有历史"（画不出线）', () {
      final e = _entry(ping: <Object?>[12], up: <Object?>[1]);
      expect(e.seriesLength, 1);
      expect(e.hasSeries, isFalse);
    });
  });

  group('连续不通与文案', () {
    test('一直在线 → 0，无文案', () {
      final e = _entry(ping: <Object?>[1, 2, 3], up: <Object?>[1, 1, 1]);
      expect(e.consecutiveDownSamples, 0);
      expect(e.downSinceLabel, isNull);
    });

    test('末尾连续 3 次不通 → 按步长换算成分钟', () {
      final e = _entry(
        ping: <Object?>[10, 11, null, null, null],
        up: <Object?>[1, 1, 0, 0, 0],
        step: 120,
      );
      expect(e.consecutiveDownSamples, 3);
      expect(e.downSinceLabel, '已不通约 6 分钟');
    });

    test('不到 1 分钟的说法要明确，不能写"0 分钟"', () {
      final e = _entry(ping: <Object?>[10, null], up: <Object?>[1, 0], step: 30);
      expect(e.downSinceLabel, '刚开始不通（不到 1 分钟）');
    });

    test('小时级与天级', () {
      final hours = _entry(
        ping: List<Object?>.filled(40, null),
        up: List<Object?>.filled(40, 0),
        step: 120,
      );
      expect(hours.downSinceLabel, '已不通约 1 小时');
      final days = _entry(
        ping: List<Object?>.filled(60, null),
        up: List<Object?>.filled(60, 0),
        step: 1800,
      );
      expect(days.downSinceLabel, '已不通超过 1 天');
    });

    test('没有序列时不乱下结论', () {
      final e = MonitorEntry.tryParse(<String, Object?>{'name': 'x', 'up': false})!;
      expect(e.consecutiveDownSamples, 0);
      expect(e.downSinceLabel, isNull, reason: '没有历史就别猜"不通多久了"');
    });
  });
}

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/local_tools/domain/local_tool_sensor.dart' as s;

/// 批次 4 纯数学单测：方位角、倾角、气泡偏移、分贝换算。
///
/// 传感器流本身在单测里拿不到（要真机），所以这里测的全是「读数 → 显示值」
/// 那一段，用注入的假读数覆盖。
void main() {
  group('指南针方位角', () {
    test('正北为 0°', () {
      expect(s.headingFromMagnetometer(x: 0, y: 1), closeTo(0, 0.01));
    });

    test('正东为 90°', () {
      expect(s.headingFromMagnetometer(x: 1, y: 0), closeTo(90, 0.01));
    });

    test('正南为 180°', () {
      expect(s.headingFromMagnetometer(x: 0, y: -1), closeTo(180, 0.01));
    });

    test('正西为 270°', () {
      expect(s.headingFromMagnetometer(x: -1, y: 0), closeTo(270, 0.01));
    });

    test('结果总落在 0~360', () {
      for (var deg = 0; deg < 360; deg += 7) {
        final rad = deg * math.pi / 180;
        final h = s.headingFromMagnetometer(x: math.sin(rad), y: math.cos(rad));
        expect(h, greaterThanOrEqualTo(0));
        expect(h, lessThan(360));
      }
    });

    test('读数为零（强磁干扰）明确报错', () {
      expect(
        () => s.headingFromMagnetometer(x: 0, y: 0),
        throwsA(isA<s.SensorToolError>()),
      );
    });
  });

  group('方位文字', () {
    test('八个方位都对得上', () {
      expect(s.headingLabel(0), '北');
      expect(s.headingLabel(45), '东北');
      expect(s.headingLabel(90), '东');
      expect(s.headingLabel(135), '东南');
      expect(s.headingLabel(180), '南');
      expect(s.headingLabel(225), '西南');
      expect(s.headingLabel(270), '西');
      expect(s.headingLabel(315), '西北');
    });

    test('边界角度归到最近方位（不出现空白）', () {
      expect(s.headingLabel(22), '北');
      expect(s.headingLabel(23), '东北');
      expect(s.headingLabel(359), '北');
    });

    test('超范围角度也能归一化', () {
      expect(s.headingLabel(360), '北');
      expect(s.headingLabel(-90), '西');
    });
  });

  group('水平仪倾角', () {
    test('平放（z 拿满）两角接近 0', () {
      final t = s.tiltFromAccelerometer(x: 0, y: 0, z: 9.81);
      expect(t.pitch, closeTo(0, 0.01));
      expect(t.roll, closeTo(0, 0.01));
    });

    test('前后倾 90°（x 拿满）pitch 到 90', () {
      final t = s.tiltFromAccelerometer(x: -9.81, y: 0, z: 0);
      expect(t.pitch, closeTo(90, 0.01));
    });

    test('左右倾 90°（y 拿满）roll 到 90', () {
      final t = s.tiltFromAccelerometer(x: 0, y: 9.81, z: 0);
      expect(t.roll, closeTo(90, 0.01));
    });

    test('读数为零报错', () {
      expect(
        () => s.tiltFromAccelerometer(x: 0, y: 0, z: 0),
        throwsA(isA<s.SensorToolError>()),
      );
    });

    test('水平判定在容差内为真', () {
      expect(s.isLevel(pitch: 0.2, roll: -0.3), isTrue);
      expect(s.isLevel(pitch: 1.2, roll: 0), isFalse);
    });
  });

  group('气泡偏移', () {
    test('完全水平时气泡在圆心', () {
      final b = s.bubbleOffset(pitch: 0, roll: 0);
      expect(b.dx, closeTo(0, 0.001));
      expect(b.dy, closeTo(0, 0.001));
    });

    test('偏移量始终在 -1~1（不会画出边界）', () {
      for (var deg = -90.0; deg <= 90; deg += 15) {
        final b = s.bubbleOffset(pitch: deg, roll: deg, maxDegrees: 15);
        expect(b.dx.abs(), lessThanOrEqualTo(1.0));
        expect(b.dy.abs(), lessThanOrEqualTo(1.0));
      }
    });

    test('达到量程时气泡贴边', () {
      final b = s.bubbleOffset(pitch: 15, roll: -15, maxDegrees: 15);
      expect(b.dy, closeTo(1.0, 0.001));
      expect(b.dx, closeTo(-1.0, 0.001));
    });

    test('小角度比大角度更灵敏（启发式曲线）', () {
      // 1° 的相对位移应该大于 10° 的十分之一 —— 这是非线性带来的手感。
      final small = s.bubbleOffset(pitch: 1, roll: 0, maxDegrees: 15).dy;
      final big = s.bubbleOffset(pitch: 10, roll: 0, maxDegrees: 15).dy;
      expect(small, greaterThan(big / 10));
    });

    test('量程非正报错', () {
      expect(
        () => s.bubbleOffset(pitch: 0, roll: 0, maxDegrees: 0),
        throwsA(isA<s.SensorToolError>()),
      );
    });
  });

  group('分贝换算', () {
    test('满幅约 0dB', () {
      expect(s.amplitudeToDb(1.0), closeTo(0, 0.01));
    });

    test('半幅约 -6dB', () {
      expect(s.amplitudeToDb(0.5), closeTo(-6.02, 0.05));
    });

    test('振幅为 0 给一个很低的读数而不是报错（静音是合法状态）', () {
      expect(s.amplitudeToDb(0), lessThan(-40));
    });

    test('负振幅报错', () {
      expect(() => s.amplitudeToDb(-0.1),
          throwsA(isA<s.SensorToolError>()));
    });

    test('offset 平移整体刻度', () {
      expect(s.amplitudeToDb(0.5, offset: 94), closeTo(87.98, 0.05));
    });

    test('分贝描述分档', () {
      expect(s.dbLabel(20), contains('安静'));
      expect(s.dbLabel(60), contains('一般'));
      expect(s.dbLabel(90), contains('嘈杂'));
      // 100 才是「非常吵」档 —— 95 落在 85~100 之间，是「嘈杂」。
      expect(s.dbLabel(100), contains('非常吵'));
      expect(s.dbLabel(105), contains('非常吵'));
    });

    test('平均值跳过无效低值', () {
      final avg = s.averageDb([-60, 50, 60, -100]);
      expect(avg, closeTo(55, 0.01));
    });

    test('全无效时报错而不是返回 0', () {
      expect(() => s.averageDb([-60, -100]),
          throwsA(isA<s.SensorToolError>()));
      expect(() => s.averageDb([]), throwsA(isA<s.SensorToolError>()));
    });
  });
}

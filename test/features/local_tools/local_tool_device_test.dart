import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/local_tools/domain/local_tool_device.dart' as d;

/// 批次 3 纯逻辑单测：随机数、摩斯密码、秒表计时、时钟格式化、刻度尺换算。
/// 传感器类（指南针/水平仪/分贝仪）需要新插件，不在本批。
void main() {
  group('随机数生成', () {
    test('落在闭区间内，且个数正确', () {
      final out = d.randomInts(min: 1, max: 6, count: 20, seed: 42);
      expect(out.length, 20);
      for (final v in out) {
        expect(v, greaterThanOrEqualTo(1));
        expect(v, lessThanOrEqualTo(6));
      }
    });

    test('同 seed 可复现', () {
      expect(
        d.randomInts(min: 0, max: 100, count: 10, seed: 7),
        d.randomInts(min: 0, max: 100, count: 10, seed: 7),
      );
    });

    test('不重复模式下无重复值', () {
      final out = d.randomInts(min: 1, max: 10, count: 10, seed: 3, unique: true);
      expect(out.toSet().length, 10);
    });

    test('不重复且要求数量超过可取值范围 → 明确报错', () {
      expect(
        () => d.randomInts(min: 1, max: 3, count: 10, seed: 1, unique: true),
        throwsA(isA<d.DeviceToolError>()),
      );
    });

    test('min > max 报错', () {
      expect(
        () => d.randomInts(min: 10, max: 1, count: 1, seed: 1),
        throwsA(isA<d.DeviceToolError>()),
      );
    });

    test('count <= 0 报错', () {
      expect(
        () => d.randomInts(min: 1, max: 10, count: 0, seed: 1),
        throwsA(isA<d.DeviceToolError>()),
      );
    });
  });

  group('摩斯密码', () {
    test('字母编码', () {
      expect(d.textToMorse('SOS'), '... --- ...');
    });

    test('数字编码', () {
      expect(d.textToMorse('1'), '.----');
    });

    test('多词用 / 分隔', () {
      expect(d.textToMorse('A B'), '.- / -...');
    });

    test('小写自动转大写', () {
      expect(d.textToMorse('sos'), d.textToMorse('SOS'));
    });

    test('解码还原', () {
      expect(d.morseToText('... --- ...'), 'SOS');
    });

    test('往返一致（含空格分词）', () {
      const s = 'HELLO WORLD 123';
      expect(d.morseToText(d.textToMorse(s)), s);
    });

    test('无法编码的字符（中文）明确报错，不静默丢弃', () {
      expect(() => d.textToMorse('中'), throwsA(isA<d.DeviceToolError>()));
    });
  });

  group('时钟格式化', () {
    test('补零到两位', () {
      expect(d.formatClock(DateTime(2026, 9, 12, 9, 5, 3)),
          '09:05:03');
    });

    test('24 小时制不出现 AM/PM', () {
      final s = d.formatClock(DateTime(2026, 9, 12, 21, 0, 0));
      expect(s, '21:00:00');
      expect(s.toUpperCase(), isNot(contains('PM')));
    });

    test('日期行格式', () {
      expect(d.formatClockDate(DateTime(2026, 9, 12, 9, 5)),
          contains('2026'));
    });
  });

  group('秒表计时', () {
    test('毫秒格式化成 mm:ss.cc', () {
      expect(d.formatStopwatch(Duration.zero), '00:00.00');
      expect(d.formatStopwatch(const Duration(milliseconds: 1234)),
          '00:01.23');
    });

    test('超过一小时给出 hh:mm:ss.cc', () {
      final s = d.formatStopwatch(
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
      expect(s, '01:02:03.00');
    });

    test('计次列表带编号与差值', () {
      final laps = d.lapDiffs([
        const Duration(seconds: 1),
        const Duration(seconds: 3),
        const Duration(seconds: 6),
      ]);
      expect(laps.length, 3);
      expect(laps[0].label, '第 1 次');
      expect(laps[0].delta, const Duration(seconds: 1));
      expect(laps[1].delta, const Duration(seconds: 2));
      expect(laps[2].delta, const Duration(seconds: 3));
    });
  });

  group('计时器倒计时', () {
    test('秒数常规格式化', () {
      expect(d.formatCountdown(const Duration(seconds: 90)), '01:30');
      expect(d.formatCountdown(const Duration(seconds: 5)), '00:05');
    });

    test('负数（已超时）钳到 00:00，不显示负号', () {
      expect(d.formatCountdown(const Duration(seconds: -3)), '00:00');
    });

    test('解析用户输入的 mm:ss', () {
      expect(d.parseCountdown('01:30'), const Duration(seconds: 90));
      expect(d.parseCountdown('90'), const Duration(seconds: 90));
    });

    test('非法输入报错', () {
      expect(() => d.parseCountdown('abc'), throwsA(isA<d.DeviceToolError>()));
      expect(() => d.parseCountdown(''), throwsA(isA<d.DeviceToolError>()));
      expect(() => d.parseCountdown('1:99'), throwsA(isA<d.DeviceToolError>()));
    });
  });

  group('刻度尺换算', () {
    test('按每逻辑像素对应的物理长度算毫米', () {
      // 假设 160 dpi：1 逻辑像素 = 1/160 英寸 = 0.15875 mm
      final mm = d.pxToMillimeters(160, 160);
      expect(mm, closeTo(25.4, 0.01));
    });

    test('dpi 非法时报错而不是除零', () {
      expect(() => d.pxToMillimeters(100, 0),
          throwsA(isA<d.DeviceToolError>()));
    });

    test('厘米换算', () {
      expect(d.mmToCm(25.4), closeTo(2.54, 0.001));
    });
  });

  group('坏点检测色板', () {
    test('色板包含纯黑与纯白（坏点最容易看出来）', () {
      expect(d.deadPixelColors, isNotEmpty);
      // 首黑尾白只是当前的排列，真正的约束是「黑白都在色板里」——
      // 用 contains 断言，将来往中间插颜色也不会误报。
      expect(d.deadPixelColors.first, 0xFF000000);
      expect(d.deadPixelColors, contains(0xFFFFFFFF));
      expect(d.deadPixelColors[1], 0xFFFFFFFF);
    });
  });
}

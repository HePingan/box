import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/local_tools/domain/local_tool_math.dart';

/// 批次 1 纯计算逻辑单测：科学计算器、单位换算、BMI、房贷、日期、时间戳、
/// 进制、大小写、随机密码、亲戚称呼。
///
/// 这些都是纯函数 —— 不联网、不依赖 Flutter、无平台通道，所以能在这里
/// 全量覆盖。UI 层只负责把输入喂进来、把结果画出去。
void main() {
  group('科学计算器', () {
    test('四则运算含优先级', () {
      expect(evalArithmetic('1+2*3'), closeTo(7, 1e-9));
      expect(evalArithmetic('(1+2)*3'), closeTo(9, 1e-9));
      expect(evalArithmetic('10/4'), closeTo(2.5, 1e-9));
      expect(evalArithmetic('2-3-4'), closeTo(-5, 1e-9));
      expect(evalArithmetic('2^3'), closeTo(8, 1e-9));
    });

    test('一元负号与小数', () {
      expect(evalArithmetic('-5+2'), closeTo(-3, 1e-9));
      expect(evalArithmetic('0.1+0.2'), closeTo(0.3, 1e-9));
    });

    test('除零与非法输入抛异常而非返回 NaN', () {
      expect(() => evalArithmetic('1/0'), throwsA(isA<LocalToolError>()));
      expect(() => evalArithmetic('1+'), throwsA(isA<LocalToolError>()));
      expect(() => evalArithmetic('abc'), throwsA(isA<LocalToolError>()));
    });
  });

  group('单位换算', () {
    test('长度：米↔厘米↔英寸↔英尺', () {
      expect(convertUnit(1, 'm', 'cm', UnitCategory.length), closeTo(100, 1e-9));
      expect(convertUnit(1, 'm', 'inch', UnitCategory.length),
          closeTo(39.3700787, 1e-6));
      expect(convertUnit(1, 'ft', 'm', UnitCategory.length),
          closeTo(0.3048, 1e-9));
    });

    test('重量：千克↔斤↔磅', () {
      expect(convertUnit(1, 'kg', 'jin', UnitCategory.weight), closeTo(2, 1e-9));
      expect(convertUnit(1, 'kg', 'lb', UnitCategory.weight),
          closeTo(2.2046226, 1e-6));
    });

    test('温度不是线性比例换算（有偏移量）', () {
      expect(convertUnit(0, 'c', 'f', UnitCategory.temperature), closeTo(32, 1e-9));
      expect(convertUnit(100, 'c', 'f', UnitCategory.temperature),
          closeTo(212, 1e-9));
      expect(convertUnit(32, 'f', 'c', UnitCategory.temperature), closeTo(0, 1e-9));
    });

    test('同单位返回原值；跨类单位报错', () {
      expect(convertUnit(7, 'm', 'm', UnitCategory.length), closeTo(7, 1e-9));
      expect(() => convertUnit(1, 'm', 'kg', UnitCategory.length),
          throwsA(isA<LocalToolError>()));
    });
  });

  group('BMI 计算', () {
    test('按中国标准分级', () {
      expect(bmiValue(70, 175), closeTo(22.857, 1e-3));
      expect(bmiCategory(bmiValue(70, 175)), '正常');
      expect(bmiCategory(17.0), '偏瘦');
      expect(bmiCategory(24.0), '超重');
      expect(bmiCategory(28.0), '肥胖');
      // 边界：24 起算超重，28 起算肥胖
      expect(bmiCategory(23.9), '正常');
      expect(bmiCategory(27.9), '超重');
    });

    test('身高体重非法报错', () {
      expect(() => bmiValue(70, 0), throwsA(isA<LocalToolError>()));
      expect(() => bmiValue(-1, 175), throwsA(isA<LocalToolError>()));
    });
  });

  group('房贷计算', () {
    test('等额本息月供', () {
      // 100 万 / 30 年 / 4.9%：月供约 5307.27
      final r = mortgageEqualInstallment(
        principal: 1000000,
        annualRatePercent: 4.9,
        months: 360,
      );
      expect(r.monthlyPayment, closeTo(5307.27, 0.05));
      expect(r.totalPayment, closeTo(1910616.0, 5));
      expect(r.totalInterest, closeTo(910616.0, 5));
    });

    test('等额本金首月最高、逐月递减', () {
      final r = mortgageEqualPrincipal(
        principal: 120000,
        annualRatePercent: 4.8,
        months: 12,
      );
      expect(r.firstMonthPayment, greaterThan(r.lastMonthPayment));
      // 本金均摊 = 10000/月
      expect(r.principalPerMonth, closeTo(10000, 1e-9));
    });

    test('零利率不炸', () {
      final r = mortgageEqualInstallment(
        principal: 120000,
        annualRatePercent: 0,
        months: 12,
      );
      expect(r.monthlyPayment, closeTo(10000, 1e-9));
      expect(r.totalInterest, closeTo(0, 1e-9));
    });

    test('非法输入报错', () {
      expect(
          () => mortgageEqualInstallment(
              principal: 0, annualRatePercent: 4.9, months: 360),
          throwsA(isA<LocalToolError>()));
      expect(
          () => mortgageEqualInstallment(
              principal: 100, annualRatePercent: 4.9, months: 0),
          throwsA(isA<LocalToolError>()));
    });
  });

  group('日期计算', () {
    test('两日期相差天数（含跨月跨年）', () {
      expect(daysBetween(DateTime(2026, 1, 1), DateTime(2026, 1, 31)), 30);
      expect(daysBetween(DateTime(2026, 1, 1), DateTime(2027, 1, 1)), 365);
      expect(daysBetween(DateTime(2026, 1, 31), DateTime(2026, 1, 1)), -30);
    });

    test('日期加减天数', () {
      expect(addDays(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 1));
      expect(addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
    });

    test('闰年判断', () {
      expect(isLeapYear(2024), isTrue);
      expect(isLeapYear(2026), isFalse);
      expect(isLeapYear(2000), isTrue);
      expect(isLeapYear(1900), isFalse);
    });
  });

  group('时间戳转换', () {
    test('秒级 ↔ 日期（本地时区不参与，用 UTC 断言）', () {
      expect(formatTimestamp(0, utc: true), '1970-01-01 00:00:00');
      expect(
        parseTimestamp('1970-01-01 00:00:00', utc: true),
        0,
      );
    });

    test('自动识别秒/毫秒', () {
      expect(normalizeTimestampToSeconds(1757664000), 1757664000);
      expect(normalizeTimestampToSeconds(1757664000000), 1757664000);
    });

    test('非法输入报错', () {
      expect(() => parseTimestamp('不是时间'), throwsA(isA<LocalToolError>()));
    });
  });

  group('进制转换', () {
    test('2/8/10/16 互转', () {
      expect(convertRadix('255', 10, 16), 'ff');
      expect(convertRadix('ff', 16, 10), '255');
      expect(convertRadix('1010', 2, 10), '10');
      expect(convertRadix('777', 8, 10), '511');
    });

    test('非法数字报错（含负数与越界基数）', () {
      expect(() => convertRadix('2', 2, 10), throwsA(isA<LocalToolError>()));
      expect(() => convertRadix('z', 16, 10), throwsA(isA<LocalToolError>()));
      expect(() => convertRadix('1', 1, 10), throwsA(isA<LocalToolError>()));
    });
  });

  group('大小写转换', () {
    test('三种模式', () {
      expect(toUpperCaseText('Abc'), 'ABC');
      expect(toLowerCaseText('AbC'), 'abc');
      expect(toTitleCase('hello world'), 'Hello World');
    });

    test('空串安全（不抛）', () {
      expect(toUpperCaseText(''), '');
      expect(toTitleCase(''), '');
    });
  });

  group('随机密码', () {
    test('长度正确且默认含大小写数字', () {
      final p = generatePassword(length: 20, seed: 42);
      expect(p.length, 20);
      expect(RegExp(r'[a-z]').hasMatch(p), isTrue);
      expect(RegExp(r'[A-Z]').hasMatch(p), isTrue);
      expect(RegExp(r'[0-9]').hasMatch(p), isTrue);
    });

    test('同种子可复现（可单测）', () {
      expect(generatePassword(length: 16, seed: 7),
          generatePassword(length: 16, seed: 7));
    });

    test('可选符号集合生效', () {
      final p = generatePassword(length: 30, seed: 1, symbols: true);
      expect(RegExp(r'[!@#\$%^&*()_+\-=\[\]{}]').hasMatch(p), isTrue);
    });

    test('长度非法报错', () {
      expect(() => generatePassword(length: 0), throwsA(isA<LocalToolError>()));
      expect(() => generatePassword(length: 200), throwsA(isA<LocalToolError>()));
    });
  });

  group('亲戚称呼计算', () {
    test('常见路径', () {
      expect(relationTitle(['爸爸', '爸爸']), '爷爷');
      expect(relationTitle(['爸爸', '妈妈']), '奶奶');
      expect(relationTitle(['妈妈', '爸爸']), '外公');
      expect(relationTitle(['妈妈', '妈妈']), '外婆');
      expect(relationTitle(['爸爸', '哥哥']), '伯父');
      expect(relationTitle(['爸爸', '弟弟']), '叔叔');
      expect(relationTitle(['爸爸', '姐姐']), '姑妈');
      expect(relationTitle(['妈妈', '哥哥']), '舅舅');
    });

    test('夫妻与子女', () {
      expect(relationTitle(['哥哥', '妻子']), '嫂子');
      expect(relationTitle(['姐姐', '丈夫']), '姐夫');
      expect(relationTitle(['爸爸', '儿子']), '兄弟');
      expect(relationTitle(['爸爸', '女儿']), '姐妹');
    });

    test('空路径 = 自己；未知路径给兜底而非崩溃', () {
      expect(relationTitle([]), '自己');
      final unknown = relationTitle(['爸爸', '爸爸', '爸爸', '爸爸']);
      expect(unknown, isNotEmpty);
    });
  });
}

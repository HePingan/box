import 'package:box/features/disguise/domain/calculator_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// 伪装计算器内核的行为测试。
///
/// 为什么值得单独测：这支假计算器**必须真能算**。算错一次、或者小数点后面
/// 按什么都没反应，伪装当场就破了。这里每一条都对应一个真实踩过的坑：
/// - `0.` 之后按数字没反应 ← `trailingNumber` 的正则写成 `\.\d+`（第一版的真 bug）；
/// - 连按运算符叠出 `+-` ← 运算符要替换而不是追加；
/// - 结果出现 `1.0` 尾巴 ← 格式化漏了去零。
void main() {
  CalculatorEngine press(String keys) {
    final engine = CalculatorEngine();
    for (final ch in keys.split('')) {
      if (ch == '.') {
        engine.inputDot();
      } else if (CalculatorEngine.operators.contains(ch)) {
        engine.inputOperator(ch);
      } else {
        engine.inputDigit(ch);
      }
    }
    return engine;
  }

  group('四则运算与优先级', () {
    test('1+1 = 2', () => expect(press('1+1').preview, '2'));
    test('先乘后加', () => expect(press('2+3×4').preview, '14'));
    test('先乘后减', () => expect(press('10−2×3').preview, '4'));
    test('连除', () => expect(press('9÷3÷3').preview, '1'));
  });

  group('小数点', () {
    test('0.1+0.2 收敛到 0.3（不留浮点尾巴）', () {
      expect(press('0.1+0.2').preview, '0.3');
    });

    test('小数点后还能继续输入', () {
      // 这条是回归测试：正则写成 `\.\d+` 时，`0.` 匹配不上，
      // 后续每个数字都被当成"开始新数字"而拒收。
      expect(press('0.15').expression, '0.15');
      expect(press('1.5×2').preview, '3');
    });

    test('重复小数点被忽略', () {
      expect(press('1..5').expression, '1.5');
    });

    test('运算符后按小数点补 0', () {
      expect(press('1+.5').expression, '1+0.5');
    });
  });

  group('运算符边界', () {
    test('连按运算符只保留最后一个', () {
      expect(press('5+×÷').expression, '5÷');
    });

    test('空表达式按运算符无效', () {
      expect(press('+').expression, '');
    });

    test('末尾小数点后接运算符补 0', () {
      final engine = press('5.');
      engine.inputOperator('+');
      expect(engine.expression, '5.0+');
    });
  });

  group('错误与残缺', () {
    test('除零给出中文提示', () {
      expect(press('8÷0').evaluate().display, kDivideByZeroMessage);
    });

    test('尾部运算符没有实时结果', () {
      expect(press('8+').preview, '');
    });

    test('空表达式求值报错', () {
      expect(CalculatorEngine().evaluate().display, kMalformedMessage);
    });
  });

  group('正负号与百分号', () {
    test('取负两次回到原值', () {
      final engine = press('5');
      engine.toggleSign();
      expect(engine.expression, '-5');
      engine.toggleSign();
      expect(engine.expression, '5');
    });

    test('百分号把当前数字除以 100', () {
      final engine = press('50+10');
      engine.percent();
      expect(engine.expression, '50+0.1');
      expect(engine.preview, '50.1');
    });
  });

  group('口令候选（解锁靠它）', () {
    test('取末尾那段纯数字', () {
      expect(press('12+3456').trailingNumber, '3456');
    });

    test('含小数点时原样返回（调用方据此判定不是口令）', () {
      expect(press('12.34').trailingNumber, '12.34');
    });

    test('末尾是运算符时没有候选', () {
      expect(press('12+').trailingNumber, '');
    });
  });

  group('等于号语义', () {
    test('算出结果', () {
      final engine = press('2+3');
      expect(engine.commit().display, '5');
    });

    test('结果可以接着算', () {
      final engine = press('2+3');
      engine.commit();
      expect(engine.expression, '5');
      engine.inputOperator('×');
      engine.inputDigit('4');
      expect(engine.preview, '20');
    });
  });

  group('格式化', () {
    test('整数不带小数尾巴', () => expect(formatNumber(4), '4'));
    test('浮点误差收敛', () => expect(formatNumber(0.1 + 0.2), '0.3'));
    test('负数', () => expect(formatNumber(-2.5), '-2.5'));
    test('零', () => expect(formatNumber(0), '0'));
  });

  group('输入长度约束', () {
    test('退格与清空', () {
      final engine = press('123');
      engine.backspace();
      expect(engine.expression, '12');
      engine.clear();
      expect(engine.expression, '');
    });

    test('退格整段删函数名，而不是一个字符一个字符地删', () {
      final engine = CalculatorEngine();
      engine.inputFunction('sin');
      expect(engine.expression, 'sin(');
      engine.backspace();
      expect(engine.expression, '');
      engine.inputConstant('π');
      engine.backspace();
      expect(engine.expression, '');
    });

    test('单个数字有位数上限', () {
      final engine = CalculatorEngine();
      for (var i = 0; i < 40; i++) {
        engine.inputDigit('9');
      }
      expect(engine.trailingNumber.length, CalculatorEngine.maxNumberLength);
    });
  });

  group('记忆键（mc / m+ / m− / mr）', () {
    test('m+ 之后 mr 能取回来', () {
      final engine = press('5');
      expect(engine.hasMemory, isFalse);
      expect(engine.memoryAdd(), isTrue);
      engine.clear();
      expect(engine.memoryRecall(), isTrue);
      expect(engine.expression, '5');
    });

    test('m− 做减法', () {
      final engine = press('10');
      engine.memoryAdd();
      engine.clear();
      engine.debugSetExpression('3');
      engine.memoryAdd(subtract: true);
      expect(engine.memory, 7);
    });

    test('mc 清空后 mr 不插入任何东西', () {
      final engine = press('5');
      engine.memoryAdd();
      engine.memoryClear();
      engine.clear();
      expect(engine.memoryRecall(), isFalse);
      expect(engine.expression, '');
    });

    test('没有结果时 m+ 不动记忆体', () {
      final engine = CalculatorEngine();
      expect(engine.memoryAdd(), isFalse);
      expect(engine.hasMemory, isFalse);
    });
  });

  group('科学功能', () {
    test('Deg 模式下 sin(30)=0.5、cos(60)=0.5', () {
      final engine = CalculatorEngine();
      engine.inputFunction('sin');
      engine.inputDigit('3');
      engine.inputDigit('0');
      engine.inputParen();
      expect(engine.preview, '0.5');

      final cosine = CalculatorEngine();
      cosine.inputFunction('cos');
      cosine.inputDigit('6');
      cosine.inputDigit('0');
      cosine.inputParen();
      expect(cosine.preview, '0.5');
    });

    test('切到 Rad 后 sin(π/2)=1', () {
      final engine = CalculatorEngine();
      engine.toggleAngleMode();
      expect(engine.angleLabel, 'Rad');
      engine.debugSetExpression('sin(π÷2)');
      expect(engine.preview, '1');
    });

    test('ln(e)=1、log(100)=2、√(9)=3', () {
      final e = CalculatorEngine();
      e.debugSetExpression('ln(e)');
      expect(e.preview, '1');

      final log = CalculatorEngine();
      log.debugSetExpression('log(100)');
      expect(log.preview, '2');

      final root = CalculatorEngine();
      root.debugSetExpression('√(9)');
      expect(root.preview, '3');
    });

    test('括号与优先级：2×(3+4)=14', () {
      final engine = CalculatorEngine();
      engine.debugSetExpression('2×(3+4)');
      expect(engine.preview, '14');
    });

    test('乘方右结合：2^3^2 = 512', () {
      final engine = CalculatorEngine();
      engine.debugSetExpression('2^3^2');
      expect(engine.preview, '512');
    });

    test('阶乘：5! = 120，小数与负数报错', () {
      final engine = CalculatorEngine();
      engine.debugSetExpression('5!');
      expect(engine.preview, '120');
      engine.debugSetExpression('2.5!');
      expect(engine.evaluate().isError, isTrue);
    });

    test('x² 与 1/x 走乘方', () {
      final square = press('5');
      square.inputSquare();
      expect(square.expression, '5^2');
      expect(square.preview, '25');

      final reciprocal = press('4');
      reciprocal.inputReciprocal();
      expect(reciprocal.expression, '4^(-1)');
      expect(reciprocal.preview, '0.25');
    });

    test('括号没配平不给结果（不是报错）', () {
      final engine = CalculatorEngine();
      engine.inputFunction('sin');
      engine.inputDigit('3');
      expect(engine.preview, '');
      expect(engine.evaluate().isError, isTrue);
    });

    test('√ 负数是格式错误而不是 NaN', () {
      final engine = CalculatorEngine();
      engine.debugSetExpression('√(0−4)');
      expect(engine.evaluate().display, kMalformedMessage);
    });
  });
}

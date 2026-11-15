import 'package:box/features/disguise/domain/disguise_settings.dart';
import 'package:box/features/disguise/presentation/calculator_disguise_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 伪装计算器的「长得像不像真机」的契约测试。
///
/// 这些断言全部来自被仿的 vivo 计算器（`com.android.bbkcalculator` 15.6.1.1）
/// APK 里的资源表：键位来自 `nex_pad_numeric` / `nex_pad_operator_one_col`，
/// 颜色来自 `color/number_text_color` 等，字号来自 `dimen/*`。
///
/// 为什么值得钉死：上一版把符号色猜成了 vivo 系统蓝 `#0F77FF`（那其实是它引用的
/// originui 组件库颜色），键位也是自己排的五列 —— 功能全对、伪装却是错的，
/// 而「颜色/键位对不对」这件事肉眼很难在 PR 里 review 出来。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<DisguiseSettings> makeSettings({String pin = '1234'}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final settings = DisguiseSettings(prefs);
    await settings.setPin(pin);
    await settings.setEnabled(true);
    return settings;
  }

  Future<DisguiseSettings> pumpCalculator(WidgetTester tester) async {
    final settings = await makeSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: CalculatorDisguisePage(settings: settings, onUnlock: () {}),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  Color? labelColor(WidgetTester tester, String label) {
    final finder = find.text(label);
    expect(finder, findsOneWidget, reason: '键位「$label」不存在');
    return tester.widget<Text>(finder).style?.color;
  }

  double? labelSize(WidgetTester tester, String label) {
    return tester.widget<Text>(find.text(label)).style?.fontSize;
  }

  group('键位与真机一致', () {
    testWidgets('数字区 3 列 × 6 行：mc m+ m- / AC % +/- / 789 / 456 / 123 / . 0 ←', (tester) async {
      await pumpCalculator(tester);
      for (final label in [
        'mc', 'm+', 'm-', //
        'AC', '%', '+/-',
        '7', '8', '9',
        '4', '5', '6',
        '1', '2', '3',
        '.', '0', '←',
      ]) {
        expect(find.text(label), findsWidgets, reason: '真机数字区有「$label」');
      }
    });

    testWidgets('运算符列 1 列 × 6 行：mr ÷ × − + =', (tester) async {
      await pumpCalculator(tester);
      for (final label in ['mr', '÷', '×', '−', '+', '=']) {
        expect(find.text(label), findsOneWidget, reason: '真机运算符列有「$label」');
      }
    });

    testWidgets('默认没有科学键（点顶部按钮才出现）', (tester) async {
      await pumpCalculator(tester);
      expect(find.text('sin'), findsNothing);
      expect(find.text('π'), findsNothing);
      expect(find.text('2nd'), findsNothing);
    });

    testWidgets('顶部有历史与科学计算器两枚按钮', (tester) async {
      await pumpCalculator(tester);
      expect(
        find.byKey(const ValueKey<String>('disguise_history_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('disguise_science_button')),
        findsOneWidget,
      );
    });
  });

  group('配色与字号来自资源表', () {
    testWidgets('数字 #595959、符号 #ED4D47、记忆键 #878787、等号白字', (tester) async {
      await pumpCalculator(tester);
      expect(labelColor(tester, '7'), const Color(0xFF595959), reason: 'number_text_color');
      expect(labelColor(tester, '9'), const Color(0xFF595959));
      expect(labelColor(tester, 'AC'), const Color(0xFFED4D47), reason: 'symbol_text_color');
      expect(labelColor(tester, '÷'), const Color(0xFFED4D47));
      expect(labelColor(tester, '+/-'), const Color(0xFFED4D47));
      expect(labelColor(tester, 'mc'), const Color(0xFF878787), reason: 'm_text_color');
      expect(labelColor(tester, 'mr'), const Color(0xFF878787));
      expect(labelColor(tester, '='), Colors.white, reason: 'equal_text_color');
    });

    testWidgets('字号：数字 23 / AC 21 / % 与 ± 25 / 运算符与等号 28', (tester) async {
      await pumpCalculator(tester);
      expect(labelSize(tester, '7'), 23);
      expect(labelSize(tester, 'AC'), 21);
      expect(labelSize(tester, '%'), 25);
      expect(labelSize(tester, '+/-'), 25);
      expect(labelSize(tester, '÷'), 28);
      expect(labelSize(tester, '='), 28);
      expect(labelSize(tester, 'mc'), 23);
    });

    testWidgets('结果行 #878787 / 28sp，公式行 48sp', (tester) async {
      await pumpCalculator(tester);
      final result = tester.widget<Text>(
        find.byKey(const ValueKey<String>('disguise_calc_result')),
      );
      expect(result.style?.color, const Color(0xFF878787));
      expect(result.style?.fontSize, 28);
      final expression = tester.widget<Text>(
        find.byKey(const ValueKey<String>('disguise_calc_expression')),
      );
      expect(expression.style?.fontSize, 48);
      expect(expression.style?.color, const Color(0xBF000000));
    });
  });

  group('Deg / Rad', () {
    testWidgets('默认 Deg，点一下变 Rad', (tester) async {
      await pumpCalculator(tester);
      expect(find.text('Deg'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('disguise_angle_mode')));
      await tester.pumpAndSettle();
      expect(find.text('Rad'), findsOneWidget);
      expect(find.text('Deg'), findsNothing);
    });

    testWidgets('Rad 模式下 sin(π/2) = 1', (tester) async {
      await pumpCalculator(tester);
      await tester.tap(find.byKey(const ValueKey<String>('disguise_angle_mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('disguise_science_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('sin'));
      await tester.pump();
      await tester.tap(find.text('π'));
      await tester.pump();
      await tester.tap(find.text('÷'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text(')'));
      await tester.pumpAndSettle();
      final result = tester.widget<Text>(
        find.byKey(const ValueKey<String>('disguise_calc_result')),
      );
      expect(result.data, '1');
    });
  });

  group('科学模式是真能算的', () {
    Future<DisguiseSettings> openScience(WidgetTester tester) async {
      final settings = await pumpCalculator(tester);
      await tester.tap(find.byKey(const ValueKey<String>('disguise_science_button')));
      await tester.pumpAndSettle();
      return settings;
    }

    testWidgets('点顶部按钮出现三行科学键', (tester) async {
      await openScience(tester);
      for (final label in [
        '2nd', 'sin', 'cos', 'tan', 'ln', //
        'π', 'e', '(', ')', '√',
        'xʸ', 'x²', '1/x', 'n!',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '科学键「$label」缺失');
      }
    });

    testWidgets('2nd 切出反三角与 log', (tester) async {
      await openScience(tester);
      await tester.tap(find.text('2nd'));
      await tester.pumpAndSettle();
      expect(find.text('sin⁻¹'), findsOneWidget);
      expect(find.text('log'), findsOneWidget);
      expect(find.text('sin'), findsNothing);
    });

    testWidgets('Deg 模式下 sin(30) = 0.5', (tester) async {
      await openScience(tester);
      await tester.tap(find.text('sin'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('0'));
      await tester.pump();
      await tester.tap(find.text(')'));
      await tester.pumpAndSettle();
      final result = tester.widget<Text>(
        find.byKey(const ValueKey<String>('disguise_calc_result')),
      );
      expect(result.data, '0.5');
    });
  });

  group('记忆键真的能用', () {
    testWidgets('m+ 存进去，AC 之后 mr 能取回来', (tester) async {
      await pumpCalculator(tester);
      await tester.tap(find.text('5'));
      await tester.pump();
      await tester.tap(find.text('m+'));
      await tester.pump();
      await tester.tap(find.text('AC'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(
          find.byKey(const ValueKey<String>('disguise_calc_expression')),
        ).data,
        '0',
      );
      await tester.tap(find.text('mr'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(
          find.byKey(const ValueKey<String>('disguise_calc_expression')),
        ).data,
        '5',
      );
    });

    testWidgets('mc 清空后 mr 什么都不做', (tester) async {
      await pumpCalculator(tester);
      await tester.tap(find.text('5'));
      await tester.pump();
      await tester.tap(find.text('m+'));
      await tester.pump();
      await tester.tap(find.text('mc'));
      await tester.pump();
      await tester.tap(find.text('AC'));
      await tester.pump();
      await tester.tap(find.text('mr'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(
          find.byKey(const ValueKey<String>('disguise_calc_expression')),
        ).data,
        '0',
      );
    });
  });

  group('历史记录', () {
    testWidgets('算过之后能在历史里看到，点条目回填结果', (tester) async {
      await pumpCalculator(tester);
      await tester.tap(find.text('7'));
      await tester.pump();
      await tester.tap(find.text('+'));
      await tester.pump();
      await tester.tap(find.text('8'));
      await tester.pump();
      await tester.tap(find.text('='));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('disguise_history_button')));
      await tester.pumpAndSettle();
      expect(find.text('历史记录'), findsOneWidget);
      expect(find.text('7+8'), findsOneWidget);
      // 公式行、结果行、历史条目各一处 → 三处
      expect(find.text('15'), findsNWidgets(3));

      await tester.tap(find.text('7+8'));
      await tester.pumpAndSettle();
      expect(find.text('历史记录'), findsNothing);
      expect(
        tester.widget<Text>(
          find.byKey(const ValueKey<String>('disguise_calc_expression')),
        ).data,
        '15',
      );
    });

    testWidgets('没有记录时显示「暂无历史记录」', (tester) async {
      await pumpCalculator(tester);
      await tester.tap(find.byKey(const ValueKey<String>('disguise_history_button')));
      await tester.pumpAndSettle();
      expect(find.text('暂无历史记录'), findsOneWidget);
      expect(find.text('清空历史记录'), findsNothing);
    });
  });
}

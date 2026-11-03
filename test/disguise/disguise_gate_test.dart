import 'package:box/features/disguise/domain/disguise_session.dart';
import 'package:box/features/disguise/domain/disguise_settings.dart';
import 'package:box/features/disguise/presentation/disguise_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 伪装闸门的行为测试。
///
/// 这是整个功能的安全边界：**锁着的时候真应用根本不该被构建**。
/// 一旦这里退化成"盖一层遮罩"，返回键、深链、底栏都能绕过去。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<DisguiseSettings> makeSettings({
    bool enabled = true,
    String? pin,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final settings = DisguiseSettings(prefs);
    if (pin != null) await settings.setPin(pin);
    if (enabled) await settings.setEnabled(true);
    return settings;
  }

  Widget wrap(DisguiseSettings settings) {
    return DisguiseGate(
      settings: settings,
      child: const MaterialApp(
        home: Scaffold(body: Center(child: Text('真应用'))),
      ),
    );
  }

  setUp(() => DisguiseSession.instance.lock());
  tearDown(() => DisguiseSession.instance.lock());

  testWidgets('没开伪装时直接进真应用', (tester) async {
    final settings = await makeSettings(enabled: false);
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    expect(find.text('真应用'), findsOneWidget);
    expect(find.text('AC'), findsNothing);
  });

  testWidgets('开着伪装时只看到计算器，真应用不存在', (tester) async {
    final settings = await makeSettings(pin: '1234');
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    expect(find.text('真应用'), findsNothing);
    expect(find.text('AC'), findsOneWidget);
    expect(find.text('='), findsOneWidget);
  });

  testWidgets('计算器能真算：1+1 显示 2', (tester) async {
    final settings = await makeSettings(pin: '4321');
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1'));
    await tester.tap(find.text('+'));
    await tester.tap(find.text('1'));
    await tester.pump();

    // 不能按文本断言：键盘上本来就有 '2' 这个按键，会同时命中两处。
    Text resultText() => tester.widget<Text>(
      find.byKey(const ValueKey<String>('disguise_calc_result')),
    );
    Text expressionText() => tester.widget<Text>(
      find.byKey(const ValueKey<String>('disguise_calc_expression')),
    );
    expect(expressionText().data, '1+1');
    expect(resultText().data, '2');
  });

  testWidgets('口令不对时按 = 只是普通计算，什么都不解锁', (tester) async {
    final settings = await makeSettings(pin: '1234');
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    for (final digit in ['9', '8', '7', '6']) {
      await tester.tap(find.text(digit));
    }
    await tester.tap(find.text('='));
    await tester.pumpAndSettle();

    // 关键：没有任何"密码错误"之类的提示，也没有进真应用。
    expect(find.text('真应用'), findsNothing);
    expect(find.textContaining('错误'), findsNothing);
    expect(find.textContaining('口令'), findsNothing);
  });

  testWidgets('口令正确时按 = 进入真应用', (tester) async {
    final settings = await makeSettings(pin: '1234');
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(find.text(digit));
    }
    await tester.tap(find.text('='));
    await tester.pumpAndSettle();

    expect(find.text('真应用'), findsOneWidget);
    expect(find.text('AC'), findsNothing);
  });

  testWidgets('解锁状态不跨实例：重新构建闸门又回到计算器', (tester) async {
    final settings = await makeSettings(pin: '1234');
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();
    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(find.text(digit));
    }
    await tester.tap(find.text('='));
    await tester.pumpAndSettle();
    expect(find.text('真应用'), findsOneWidget);

    // 模拟"杀掉进程再打开"：会话被重置，闸门重新构建。
    DisguiseSession.instance.lock();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    expect(find.text('AC'), findsOneWidget);
    expect(find.text('真应用'), findsNothing);
  });

  /// 按住结果行的手势。分两步 pump 是必须的：
  ///
  /// `onTapDown` 要等 TapGestureRecognizer 的 kPressTimeout（100ms）才发，
  /// 一步 `pump(5s)` 会让 tapDown 和那 5 秒计时器挤在同一刻出发 —— 计时器
  /// 到期末尾才被排进去，等于永远不触发，测试就会「假绿」。
  Future<void> holdResultRow(
    WidgetTester tester, {
    Duration hold = const Duration(seconds: 5),
  }) async {
    // 必须点 GestureDetector 本身：结果文本为空串时宽度为 0，它的中心落在
    // 父容器右边界上，而 hit test 的右边界是开区间 —— 按文本中心点会打空。
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey<String>('disguise_hold_target')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(hold + const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// 造一份「开着伪装 + 有口令 + 有恢复码」的设置，返回明文恢复码。
  Future<(DisguiseSettings, String)> makeRecoverySettings({
    String pin = '1234',
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final settings = DisguiseSettings(prefs);
    await settings.setPin(pin);
    await settings.setEnabled(true);
    final code = await settings.issueRecoveryCode();
    return (settings, code!);
  }

  testWidgets('按住结果行不到 5 秒不弹任何东西', (tester) async {
    final (settings, _) = await makeRecoverySettings();
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    await holdResultRow(tester, hold: const Duration(seconds: 3));

    expect(find.text('恢复码'), findsNothing);
    expect(find.text('AC'), findsOneWidget);
  });

  testWidgets('没有恢复码时按住 5 秒：说实话，不假装是码错了', (tester) async {
    final settings = await makeSettings(pin: '1234');
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    await holdResultRow(tester);

    expect(find.text('没有可用的恢复码'), findsOneWidget);
    expect(find.text('真应用'), findsNothing);
  });

  testWidgets('恢复码不对：留在框里提示，不解锁也不改口令', (tester) async {
    final (settings, recovery) = await makeRecoverySettings();
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    await holdResultRow(tester);
    expect(find.text('恢复码'), findsOneWidget);

    final wrong =
        recovery.substring(0, recovery.length - 1) +
        (recovery.endsWith('2') ? '3' : '2');
    await tester.enterText(find.byType(TextField), wrong);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('恢复码不对'), findsOneWidget);
    expect(find.text('真应用'), findsNothing);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('AC'), findsOneWidget);
    expect(settings.verifyPin('1234'), isTrue);
  });

  testWidgets('恢复码正确：重设口令 → 轮换恢复码 → 进真应用', (tester) async {
    final (settings, recovery) = await makeRecoverySettings();
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    await holdResultRow(tester);

    // 1) 恢复码
    await tester.enterText(find.byType(TextField), recovery);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 2) 新口令
    expect(find.text('设置新口令'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '8642');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 3) 确认口令
    expect(find.text('再输一次'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '8642');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 4) 旧码作废、新码显示一次
    final codeFinder = find.byKey(
      const ValueKey<String>('disguise_recovery_code'),
    );
    expect(find.text('新的恢复码'), findsOneWidget);
    expect(codeFinder, findsOneWidget);
    final rotated = tester.widget<SelectableText>(codeFinder).data!;
    expect(rotated, isNot(recovery));

    await tester.tap(find.text('我已抄下'));
    await tester.pumpAndSettle();

    // 5) 真的进来了，而且口令换成了新的
    expect(find.text('真应用'), findsOneWidget);
    expect(find.text('AC'), findsNothing);
    expect(settings.verifyPin('8642'), isTrue);
    expect(settings.verifyPin('1234'), isFalse);
    expect(settings.verifyRecoveryCode(recovery), isFalse);
    expect(settings.verifyRecoveryCode(rotated), isTrue);
  });

  testWidgets('新口令两次不一致：不许解锁', (tester) async {
    final (settings, recovery) = await makeRecoverySettings();
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    await holdResultRow(tester);
    await tester.enterText(find.byType(TextField), recovery);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '8642');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '8643');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('两次输入不一致'), findsOneWidget);
    expect(find.text('真应用'), findsNothing);
    expect(settings.verifyPin('1234'), isTrue);
  });

  testWidgets('长按 = 的触发方式弹出输入框', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final settings = DisguiseSettings(prefs);
    await settings.setPin('1234');
    await settings.setEnabled(true);
    await settings.setTrigger(DisguiseTrigger.longPress);

    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('='));
    await tester.pumpAndSettle();
    expect(find.text('输入口令'), findsOneWidget);
  });
}

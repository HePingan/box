import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/calculator_engine.dart';
import '../domain/disguise_settings.dart';
import 'recovery_code_sheet.dart';
import 'text_prompt_dialog.dart';

/// 按住结果行多久算「要求恢复」。
///
/// 5 秒的理由：短于这个数，普通人翻找计算记录时会误触；长于这个数，
/// 真的忘了口令的人会以为这功能不存在。它同时是「别人不知道有这条后门」的
/// 唯一屏障 —— 所以这个数字不许缩短成 1 秒那种"顺手就能碰出来"的量级。
const Duration kRecoveryHold = Duration(seconds: 5);

/// 伪装用的计算器界面。
///
/// 目标只有一个：**旁人拿起来按，得到的就是这支计算器该有的样子**。
/// 所以它不是一张静态假图，而是一个能真算的计算器（[CalculatorEngine]）。
///
/// 外观对齐被仿的那支 vivo 计算器（`com.android.bbkcalculator` 15.6.1.1）
/// 的实测值：白底、公式行 48sp 黑 `#BF000000`、结果行 28sp 灰 `#878787`、
/// monospace、右对齐、键位扁平无底色、`=` 是 vivo 蓝 `#0F77FF` 实心键。
///
/// ## 解锁：任何时候都不许露出「这是个锁」的痕迹
///
/// - 口令按 [DisguiseSettings.trigger] 触发：默认「输完数字按 `=`」；
/// - 口令**不对时走正常计算流程**：显示结果、没有任何提示、没有延迟、没有抖动、
///   没有「密码错误」——任何可观察的差异都会让伪装被识破；
/// - 口令对时立刻切到真应用（[onUnlock]）。
///
/// 副作用是：如果用户的口令恰好是一道普通算式的结果（例如口令 `2024`，
/// 而他要算 `2000+24`），那一下会解锁。这是可接受的取舍 —— 伪装优先，
/// 而且用户自己知道口令是什么。
class CalculatorDisguisePage extends StatefulWidget {
  const CalculatorDisguisePage({
    super.key,
    required this.settings,
    required this.onUnlock,
  });

  final DisguiseSettings settings;
  final VoidCallback onUnlock;

  @override
  State<CalculatorDisguisePage> createState() => _CalculatorDisguisePageState();
}

class _CalculatorDisguisePageState extends State<CalculatorDisguisePage> {
  final CalculatorEngine _engine = CalculatorEngine();

  /// 结果行显示的内容。空闲时是实时预览，按过 `=` 后是最终结果。
  String _resultText = '';

  /// 按住结果行的计时（见 [kRecoveryHold]）。
  Timer? _holdTimer;
  bool _holdElapsed = false;

  static const Color _background = Color(0xFFFFFFFF);
  static const Color _expressionColor = Color(0xBF000000);
  static const Color _resultColor = Color(0xFF878787);
  static const Color _accent = Color(0xFF0F77FF);

  @override
  void initState() {
    super.initState();
    // 计算器界面必须是「白底 + 深色状态栏图标」，与 vivo 计算器一致；
    // 退出伪装后由 App 自己的 applySystemUi() 接管，不需要在这里恢复。
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: _background,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: _background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _resultText = _engine.preview;
    });
  }

  /// 处理一次按键。口令命中则解锁并终止本次按键。
  bool _tryUnlock(String? candidate) {
    if (candidate == null || candidate.isEmpty) return false;
    if (!DisguiseSettings.isValidPin(candidate)) return false;
    if (!widget.settings.verifyPin(candidate)) return false;
    widget.onUnlock();
    return true;
  }

  void _onDigit(String digit) {
    HapticFeedback.selectionClick();
    _engine.inputDigit(digit);
    _refresh();
  }

  void _onDot() {
    HapticFeedback.selectionClick();
    _engine.inputDot();
    _refresh();
  }

  void _onOperator(String op) {
    HapticFeedback.selectionClick();
    _engine.inputOperator(op);
    _refresh();
  }

  void _onPercent() {
    HapticFeedback.selectionClick();
    _engine.percent();
    _refresh();
  }

  void _onToggleSign() {
    HapticFeedback.selectionClick();
    _engine.toggleSign();
    _refresh();
  }

  void _onClear() {
    HapticFeedback.selectionClick();
    _engine.clear();
    _refresh();
  }

  void _onBackspace() {
    HapticFeedback.selectionClick();
    _engine.backspace();
    _refresh();
  }

  /// `=`：先看是不是口令，否则当普通计算结算。
  void _onEquals() {
    HapticFeedback.selectionClick();
    if (widget.settings.trigger == DisguiseTrigger.equals) {
      if (_tryUnlock(_engine.trailingNumber)) return;
    }
    final result = _engine.commit();
    setState(() => _resultText = result.display);
  }

  /// 长按 `=`：只有把触发方式设成「长按 = 输入口令」时才挂载这个入口。
  Future<void> _onEqualsLongPress() async {
    if (widget.settings.trigger != DisguiseTrigger.longPress) return;
    HapticFeedback.mediumImpact();
    final pin = await _askText(
      title: '输入口令',
      hint: '口令',
      obscure: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validate: (_) => null,
    );
    if (pin == null || pin.isEmpty) return;
    if (_tryUnlock(pin)) return;
    // 不对就什么都不发生 —— 用户看到的就是「按了没关系」。
  }

  // ——— 忘了口令时的后门：按住结果行 5 秒 ———

  /// 用 `Timer` 而不是记一个 `DateTime` 起始时刻：widget 测试跑的是假时钟，
  /// 只有 `Timer` 能被 `tester.pump(5s)` 推进。这条逻辑必须能被测到，
  /// 因为它决定「后门什么时候出现」，靠肉眼是验不出边界的。
  void _onHoldStart(TapDownDetails _) {
    _holdElapsed = false;
    _holdTimer?.cancel();
    _holdTimer = Timer(kRecoveryHold, () => _holdElapsed = true);
  }

  /// 只在**松手之后**弹框。
  ///
  /// 按住满 5 秒就弹的话，手机还贴在手指下面，松手那一下会落在对话框的
  /// barrier 上把它关掉 —— 用户会看到框闪了一下就没了。
  void _onHoldEnd(TapUpDetails _) {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (!_holdElapsed) return;
    _holdElapsed = false;
    HapticFeedback.selectionClick();
    unawaited(_startRecovery());
  }

  void _onHoldCancel() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdElapsed = false;
  }

  /// 恢复流程：验证恢复码 → 重设口令 → 轮换恢复码 → 进真应用。
  ///
  /// 每一步失败就停在那一步，不自动回退重试：这是解锁路径，宁可让用户重新
  /// 按住 5 秒，也不要留下任何可以被反复试探的循环。
  Future<void> _startRecovery() async {
    if (!widget.settings.hasRecoveryCode) {
      await _showNotice('没有可用的恢复码', '这台设备没有生成过恢复码。伪装开着时只能清除应用数据后重新设置。');
      return;
    }

    final code = await _askText(
      title: '恢复码',
      hint: 'XXXX-XXXX-XXXX-XXXX',
      keyboardType: TextInputType.visiblePassword,
      validate: (value) =>
          widget.settings.verifyRecoveryCode(value) ? null : '恢复码不对',
    );
    if (code == null || !mounted) return;

    final newPin = await _askNewPin();
    if (newPin == null || !mounted) return;

    await widget.settings.setPin(newPin);
    // 用过的恢复码立刻作废：如果有人真的瞄到过它，也是在这一刻失效。
    final rotated = await widget.settings.issueRecoveryCode();
    if (!mounted) return;
    if (rotated != null) {
      await showRecoveryCodeDialog(
        context,
        rotated,
        title: '新的恢复码',
        subtitle: '旧恢复码已作废。',
      );
    }
    if (!mounted) return;
    widget.onUnlock();
  }

  /// 设置新口令：输一遍 + 确认一遍。
  Future<String?> _askNewPin() async {
    final first = await _askText(
      title: '设置新口令',
      hint:
          '${DisguiseSettings.minPinLength}–${DisguiseSettings.maxPinLength} 位数字',
      obscure: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validate: (value) => DisguiseSettings.isValidPin(value)
          ? null
          : '必须是 ${DisguiseSettings.minPinLength}–'
                '${DisguiseSettings.maxPinLength} 位数字',
    );
    if (first == null || !mounted) return null;

    return _askText(
      title: '再输一次',
      hint: '确认刚才的口令',
      obscure: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validate: (value) => value == first ? null : '两次输入不一致',
    );
  }

  /// 统一输入框：校验不通过就**留在框里**显示原因，而不是关掉框什么都不说。
  ///
  /// 注意这里可以有错误提示 —— 「没有提示」那条规矩只约束计算器界面本身：
  /// 走到这个框的时候，对方已经知道这不是一支计算器了，再沉默只会伤到
  /// 真的忘了口令的机主。
  Future<String?> _askText({
    required String title,
    required String hint,
    required String? Function(String value) validate,
    bool obscure = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return showTextPrompt(
      context,
      title: title,
      hint: hint,
      validate: validate,
      obscure: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      // 对话框也用计算器那张白纸，不要突然弹一块跟随应用主题的卡片。
      backgroundColor: _background,
      textColor: const Color(0xFF1A1A1A),
    );
  }

  Future<void> _showNotice(String title, String body) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _background,
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, color: Color(0xFF1A1A1A)),
        ),
        content: Text(
          body,
          style: const TextStyle(
            fontSize: 14,
            height: 1.6,
            color: Color(0xFF1A1A1A),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _background,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: _background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: _buildDisplay()),
              _buildKeypad(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDisplay() {
    final expression = _engine.expression;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Text(
                  expression.isEmpty ? '0' : expression,
                  // 键名是给测试用的接缝：键盘上也有 '2' 这个字，
                  // 按文本断言会同时命中按键，只有按 Key 取才说明"结果行"是什么。
                  key: const ValueKey<String>('disguise_calc_expression'),
                  maxLines: 1,
                  style: const TextStyle(
                    color: _expressionColor,
                    fontSize: 48,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w400,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 结果行是唯一挂「按住进入恢复」的位置：它不属于任何可滚区域，
          // 长按不会和横滑抢手势；而键盘每个键都必须是纯输入，不许藏暗门。
          GestureDetector(
            key: const ValueKey<String>('disguise_hold_target'),
            behavior: HitTestBehavior.opaque,
            onTapDown: _onHoldStart,
            onTapUp: _onHoldEnd,
            onTapCancel: _onHoldCancel,
            child: SizedBox(
              height: 36,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _resultText,
                  key: const ValueKey<String>('disguise_calc_result'),
                  maxLines: 1,
                  style: const TextStyle(
                    color: _resultColor,
                    fontSize: 28,
                    fontFamily: 'monospace',
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeypad() {
    final rows = <List<_CalcKey>>[
      [
        _CalcKey('AC', _KeyKind.function, onTap: _onClear),
        _CalcKey('⌫', _KeyKind.function, onTap: _onBackspace),
        _CalcKey('%', _KeyKind.function, onTap: _onPercent),
        _CalcKey('÷', _KeyKind.operator, onTap: () => _onOperator('÷')),
      ],
      [
        _CalcKey('7', _KeyKind.digit, onTap: () => _onDigit('7')),
        _CalcKey('8', _KeyKind.digit, onTap: () => _onDigit('8')),
        _CalcKey('9', _KeyKind.digit, onTap: () => _onDigit('9')),
        _CalcKey('×', _KeyKind.operator, onTap: () => _onOperator('×')),
      ],
      [
        _CalcKey('4', _KeyKind.digit, onTap: () => _onDigit('4')),
        _CalcKey('5', _KeyKind.digit, onTap: () => _onDigit('5')),
        _CalcKey('6', _KeyKind.digit, onTap: () => _onDigit('6')),
        _CalcKey('−', _KeyKind.operator, onTap: () => _onOperator('−')),
      ],
      [
        _CalcKey('1', _KeyKind.digit, onTap: () => _onDigit('1')),
        _CalcKey('2', _KeyKind.digit, onTap: () => _onDigit('2')),
        _CalcKey('3', _KeyKind.digit, onTap: () => _onDigit('3')),
        _CalcKey('+', _KeyKind.operator, onTap: () => _onOperator('+')),
      ],
      [
        _CalcKey('±', _KeyKind.function, onTap: _onToggleSign),
        _CalcKey('0', _KeyKind.digit, onTap: () => _onDigit('0')),
        _CalcKey('.', _KeyKind.digit, onTap: _onDot),
        _CalcKey(
          '=',
          _KeyKind.equals,
          onTap: _onEquals,
          onLongPress: _onEqualsLongPress,
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in rows)
            Row(
              children: [
                for (final key in row) Expanded(child: _buildKey(key)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildKey(_CalcKey key) {
    final bool isEquals = key.kind == _KeyKind.equals;
    final Color textColor = isEquals
        ? Colors.white
        : key.kind == _KeyKind.function || key.kind == _KeyKind.operator
        ? _accent
        : const Color(0xFF1A1A1A);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: key.onTap,
        onLongPress: key.onLongPress,
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: isEquals ? _accent : Colors.transparent,
            // 键位参照 vivo：数字/运算符是扁平无底色的，只有 `=` 是实心块。
            borderRadius: BorderRadius.circular(isEquals ? 16 : 8),
          ),
          alignment: Alignment.center,
          child: Text(
            key.label,
            style: TextStyle(
              fontSize: key.kind == _KeyKind.digit ? 26 : 24,
              fontWeight: FontWeight.w400,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

enum _KeyKind { digit, operator, function, equals }

class _CalcKey {
  const _CalcKey(
    this.label,
    this.kind, {
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final _KeyKind kind;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
}

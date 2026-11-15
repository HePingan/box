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

/// 一条历史记录（真机的历史面板就是「表达式 + 结果」两行）。
class _HistoryEntry {
  const _HistoryEntry(this.expression, this.result);

  final String expression;
  final String result;
}

/// 伪装用的计算器界面。
///
/// 目标只有一个：**旁人拿起来按，得到的就是这支计算器该有的样子**。
/// 所以它不是一张静态假图，而是一个能真算的计算器（[CalculatorEngine]）。
///
/// 外观与键位对齐被仿的那支 vivo 计算器（`com.android.bbkcalculator` 15.6.1.1）。
/// 下面这些数值不是估的，是从它 APK 的资源表里读出来的
/// （`nex_activity_calculator_port` / `nex_pad_numeric` /
/// `nex_pad_operator_one_col` 与相关 color/dimen/style）：
///
/// - 底色 `#F8F8F8`（`color/calculator_background`），键区 `#FAFAFA`；
/// - 公式行 48sp `#BF000000`（`dimen/input_size`、`color/edit_text_color`），
///   结果行 28sp `#878787`（`dimen/result_size`、`color/result_text_color`）；
/// - 数字 `#595959`（`number_text_color`）、运算符与 AC/%/± `#ED4D47`
///   （`symbol_text_color`）、记忆键 mc/m+/m−/mr 与科学函数键 `#878787`
///   （`m_text_color` / `fun_text_color`）、`=` 是白字 +
///   `#ED4D47` 圆角实心块（`equal_text_color` + `radius_size` 30dp）；
/// - 字号：数字 23、AC 21、% 与 ± 25、运算符与 `=` 28、记忆键 23、顶部 Deg/Rad 12；
/// - 键区六行四列：`mc m+ m− | mr` / `AC % +/- | ÷` / `7 8 9 | ×` /
///   `4 5 6 | −` / `1 2 3 | +` / `. 0 ← | =`；
/// - 顶部右侧两枚 42dp 按钮：历史、科学计算器切换。
///
/// 上一版把这些猜错了：符号色用了 vivo 系统蓝 `#0F77FF`（那其实是 originui
/// 组件库的颜色，不是这支应用的调色板），键位也是自己排的五列 —— 真机一眼能看出差别。
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

  /// 科学模式（顶部右侧那枚按钮）。
  bool _scienceMode = false;

  /// 科学模式的 2nd 页（反三角 / log）。
  bool _secondPage = false;

  /// 本次会话的历史记录。真机把它存盘，我们只在内存里留一份：
  /// 旁人的使用手感一样，而不落盘反而更安全。
  final List<_HistoryEntry> _history = <_HistoryEntry>[];

  static const Color _background = Color(0xFFF8F8F8);
  static const Color _padBackground = Color(0xFFFAFAFA);
  static const Color _expressionColor = Color(0xBF000000);
  static const Color _resultColor = Color(0xFF878787);
  static const Color _numberColor = Color(0xFF595959);
  static const Color _symbolColor = Color(0xFFED4D47);
  static const Color _iconColor = Color(0xFF333333);

  @override
  void initState() {
    super.initState();
    // 计算器界面必须是「浅色底 + 深色状态栏图标」，与 vivo 计算器一致；
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

  void _touch() => HapticFeedback.selectionClick();

  /// 处理一次按键。口令命中则解锁并终止本次按键。
  bool _tryUnlock(String? candidate) {
    if (candidate == null || candidate.isEmpty) return false;
    if (!DisguiseSettings.isValidPin(candidate)) return false;
    if (!widget.settings.verifyPin(candidate)) return false;
    widget.onUnlock();
    return true;
  }

  void _onDigit(String digit) {
    _touch();
    if (_engine.inputDigit(digit)) _refresh();
  }

  void _onDot() {
    _touch();
    if (_engine.inputDot()) _refresh();
  }

  void _onOperator(String op) {
    _touch();
    if (_engine.inputOperator(op)) _refresh();
  }

  void _onPercent() {
    _touch();
    if (_engine.percent()) _refresh();
  }

  void _onToggleSign() {
    _touch();
    if (_engine.toggleSign()) _refresh();
  }

  void _onClear() {
    _touch();
    _engine.clear();
    _refresh();
  }

  void _onBackspace() {
    _touch();
    _engine.backspace();
    _refresh();
  }

  void _onFunction(String name) {
    _touch();
    if (_engine.inputFunction(name)) _refresh();
  }

  void _onConstant(String constant) {
    _touch();
    if (_engine.inputConstant(constant)) _refresh();
  }

  void _onParen() {
    _touch();
    if (_engine.inputParen()) _refresh();
  }

  void _onPower() {
    _touch();
    if (_engine.inputPower()) _refresh();
  }

  void _onFactorial() {
    _touch();
    if (_engine.inputFactorial()) _refresh();
  }

  void _onSquare() {
    _touch();
    if (_engine.inputSquare()) _refresh();
  }

  void _onReciprocal() {
    _touch();
    if (_engine.inputReciprocal()) _refresh();
  }

  void _onMemoryClear() {
    _touch();
    if (_engine.memoryClear()) setState(() {});
  }

  void _onMemoryAdd({required bool subtract}) {
    _touch();
    if (_engine.memoryAdd(subtract: subtract)) setState(() {});
  }

  void _onMemoryRecall() {
    _touch();
    if (_engine.memoryRecall()) _refresh();
  }

  void _onAngleMode() {
    _touch();
    setState(_engine.toggleAngleMode);
  }

  /// `=`：先看是不是口令，否则当普通计算结算。
  void _onEquals() {
    _touch();
    if (widget.settings.trigger == DisguiseTrigger.equals) {
      if (_tryUnlock(_engine.trailingNumber)) return;
    }
    final before = _engine.expression;
    final result = _engine.commit();
    if (before.isNotEmpty && before != result.display) {
      _history.add(_HistoryEntry(before, result.display));
    }
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

  // ——— 历史记录 ———

  Future<void> _openHistory() async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _background,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Text(
                    '历史记录',
                    style: TextStyle(
                      fontSize: 16,
                      color: _numberColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _history.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Text(
                        '暂无历史记录',
                        style: TextStyle(fontSize: 14, color: _resultColor),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _history.length,
                      itemBuilder: (_, index) {
                        final entry = _history[_history.length - 1 - index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            entry.expression,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontSize: 14,
                              color: _resultColor,
                            ),
                          ),
                          subtitle: Text(
                            entry.result,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontSize: 20,
                              color: _expressionColor,
                            ),
                          ),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _engine.debugSetExpression(entry.result);
                            _refresh();
                          },
                        );
                      },
                    ),
            ),
            if (_history.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  setState(_history.clear);
                },
                child: const Text(
                  '清空历史记录',
                  style: TextStyle(fontSize: 14, color: _symbolColor),
                ),
              ),
          ],
        ),
      ),
    );
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
              Expanded(flex: 4, child: _buildDisplay()),
              _buildToolbar(),
              Expanded(flex: 6, child: _buildKeypad()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDisplay() {
    final expression = _engine.expression;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Deg / Rad：真机在显示区左上角放一枚 12sp 的 `#878787` 小字，点它切模式。
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              key: const ValueKey<String>('disguise_angle_mode'),
              behavior: HitTestBehavior.opaque,
              onTap: _onAngleMode,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                child: Text(
                  _engine.angleLabel,
                  style: const TextStyle(fontSize: 12, color: _resultColor),
                ),
              ),
            ),
          ),
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
          const SizedBox(height: 2),
          // 结果行是唯一挂「按住进入恢复」的位置：它不属于任何可滚区域，
          // 长按不会和横滑抢手势；而键盘每个键都必须是纯输入，不许藏暗门。
          GestureDetector(
            key: const ValueKey<String>('disguise_hold_target'),
            behavior: HitTestBehavior.opaque,
            onTapDown: _onHoldStart,
            onTapUp: _onHoldEnd,
            onTapCancel: _onHoldCancel,
            child: SizedBox(
              height: 34,
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

  /// 显示区下面那两枚 42dp 按钮：历史、科学计算器切换（真机同位置同大小）。
  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildIconButton(
            buttonKey: const ValueKey<String>('disguise_history_button'),
            icon: Icons.history,
            onTap: _openHistory,
          ),
          const SizedBox(width: 8),
          _buildIconButton(
            buttonKey: const ValueKey<String>('disguise_science_button'),
            icon: Icons.functions,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _scienceMode = !_scienceMode;
                _secondPage = false;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required Key buttonKey,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: buttonKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 42,
        height: 42,
        child: Icon(icon, size: 24, color: _iconColor),
      ),
    );
  }

  Widget _buildKeypad() {
    return Container(
      color: _padBackground,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        children: [
          if (_scienceMode) Expanded(flex: 3, child: _buildScienceBlock()),
          Expanded(
            flex: 6,
            child: Row(
              children: [
                Expanded(flex: 3, child: _buildNumericBlock()),
                Expanded(flex: 1, child: _buildOperatorBlock()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 科学模式的三行函数键（真机的科学键是运行时代码塞进去的，布局不可考，
  /// 这里按同一套视觉语言排：2nd / 三角函数 / 常量与括号 / 幂与阶乘）。
  Widget _buildScienceBlock() {
    final second = _secondPage;
    return Column(
      children: [
        Expanded(
          child: _buildKeyRow([
            _KeySpec(
              '2nd',
              _KeyKind.function,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _secondPage = !_secondPage);
              },
            ),
            _KeySpec(
              second ? 'sin⁻¹' : 'sin',
              _KeyKind.function,
              onTap: () => _onFunction(second ? 'asin' : 'sin'),
            ),
            _KeySpec(
              second ? 'cos⁻¹' : 'cos',
              _KeyKind.function,
              onTap: () => _onFunction(second ? 'acos' : 'cos'),
            ),
            _KeySpec(
              second ? 'tan⁻¹' : 'tan',
              _KeyKind.function,
              onTap: () => _onFunction(second ? 'atan' : 'tan'),
            ),
            _KeySpec(
              second ? 'log' : 'ln',
              _KeyKind.function,
              onTap: () => _onFunction(second ? 'log' : 'ln'),
            ),
          ]),
        ),
        Expanded(
          child: _buildKeyRow([
            _KeySpec('π', _KeyKind.function, onTap: () => _onConstant('π')),
            _KeySpec('e', _KeyKind.function, onTap: () => _onConstant('e')),
            _KeySpec('(', _KeyKind.function, onTap: _onParen),
            _KeySpec(')', _KeyKind.function, onTap: _onParen),
            _KeySpec('√', _KeyKind.function, onTap: () => _onFunction('√')),
          ]),
        ),
        Expanded(
          child: _buildKeyRow([
            _KeySpec('xʸ', _KeyKind.function, onTap: _onPower),
            _KeySpec('x²', _KeyKind.function, onTap: _onSquare),
            _KeySpec('1/x', _KeyKind.function, onTap: _onReciprocal),
            _KeySpec('n!', _KeyKind.function, onTap: _onFactorial),
            _KeySpec('←', _KeyKind.function, onTap: _onBackspace),
          ]),
        ),
      ],
    );
  }

  /// 数字区：三列六行（真机 `nex_pad_numeric` 的顺序）。
  Widget _buildNumericBlock() {
    final rows = <List<_KeySpec>>[
      [
        _KeySpec('mc', _KeyKind.memory, onTap: _onMemoryClear),
        _KeySpec('m+', _KeyKind.memory, onTap: () => _onMemoryAdd(subtract: false)),
        _KeySpec('m-', _KeyKind.memory, onTap: () => _onMemoryAdd(subtract: true)),
      ],
      [
        _KeySpec('AC', _KeyKind.symbol, fontSize: 21, onTap: _onClear),
        _KeySpec('%', _KeyKind.symbol, fontSize: 25, onTap: _onPercent),
        _KeySpec('+/-', _KeyKind.symbol, fontSize: 25, onTap: _onToggleSign),
      ],
      [
        _KeySpec('7', _KeyKind.number, onTap: () => _onDigit('7')),
        _KeySpec('8', _KeyKind.number, onTap: () => _onDigit('8')),
        _KeySpec('9', _KeyKind.number, onTap: () => _onDigit('9')),
      ],
      [
        _KeySpec('4', _KeyKind.number, onTap: () => _onDigit('4')),
        _KeySpec('5', _KeyKind.number, onTap: () => _onDigit('5')),
        _KeySpec('6', _KeyKind.number, onTap: () => _onDigit('6')),
      ],
      [
        _KeySpec('1', _KeyKind.number, onTap: () => _onDigit('1')),
        _KeySpec('2', _KeyKind.number, onTap: () => _onDigit('2')),
        _KeySpec('3', _KeyKind.number, onTap: () => _onDigit('3')),
      ],
      [
        _KeySpec('.', _KeyKind.number, onTap: _onDot),
        _KeySpec('0', _KeyKind.number, onTap: () => _onDigit('0')),
        _KeySpec('←', _KeyKind.number, onTap: _onBackspace),
      ],
    ];
    return Column(
      children: [
        for (final row in rows) Expanded(child: _buildKeyRow(row)),
      ],
    );
  }

  /// 运算符区：一列六行 `mr ÷ × − + =`（真机 `nex_pad_operator_one_col`）。
  Widget _buildOperatorBlock() {
    final rows = <List<_KeySpec>>[
      [_KeySpec('mr', _KeyKind.memory, onTap: _onMemoryRecall)],
      [_KeySpec('÷', _KeyKind.symbol, onTap: () => _onOperator('÷'))],
      [_KeySpec('×', _KeyKind.symbol, onTap: () => _onOperator('×'))],
      [_KeySpec('−', _KeyKind.symbol, onTap: () => _onOperator('−'))],
      [_KeySpec('+', _KeyKind.symbol, onTap: () => _onOperator('+'))],
      [
        _KeySpec(
          '=',
          _KeyKind.equals,
          onTap: _onEquals,
          onLongPress: _onEqualsLongPress,
        ),
      ],
    ];
    return Column(
      children: [
        for (final row in rows) Expanded(child: _buildKeyRow(row)),
      ],
    );
  }

  Widget _buildKeyRow(List<_KeySpec> specs) {
    return Row(
      children: [
        for (final spec in specs) Expanded(child: _CalcKeyButton(spec: spec)),
      ],
    );
  }
}

enum _KeyKind { number, symbol, memory, function, equals }

class _KeySpec {
  const _KeySpec(
    this.label,
    this.kind, {
    required this.onTap,
    this.onLongPress,
    this.fontSize,
  });

  final String label;
  final _KeyKind kind;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double? fontSize;
}

/// 单个键。按压反馈是 `#E0E0E0` 的圆角块（真机 `number_press_background_color`）——
/// 少了它，按下去毫无回应，手感「像假的」，这本身就是破绽。
class _CalcKeyButton extends StatefulWidget {
  const _CalcKeyButton({required this.spec});

  final _KeySpec spec;

  @override
  State<_CalcKeyButton> createState() => _CalcKeyButtonState();
}

class _CalcKeyButtonState extends State<_CalcKeyButton> {
  bool _pressed = false;

  static const Color _numberColor = Color(0xFF595959);
  static const Color _symbolColor = Color(0xFFED4D47);
  static const Color _memoryColor = Color(0xFF878787);
  static const Color _pressColor = Color(0xFFE0E0E0);

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final bool isEquals = spec.kind == _KeyKind.equals;
    final Color color = switch (spec.kind) {
      _KeyKind.number => _numberColor,
      _KeyKind.symbol => _symbolColor,
      _KeyKind.memory => _memoryColor,
      _KeyKind.function => _memoryColor,
      _KeyKind.equals => Colors.white,
    };
    final double fontSize = spec.fontSize ??
        switch (spec.kind) {
          _KeyKind.number => 23,
          _KeyKind.memory => 23,
          _KeyKind.function => 20,
          _KeyKind.symbol => 28,
          _KeyKind.equals => 28,
        };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: spec.onTap,
      onLongPress: spec.onLongPress,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          decoration: BoxDecoration(
            color: isEquals
                ? _symbolColor
                : (_pressed ? _pressColor : Colors.transparent),
            // `=` 是圆角 30dp 的实心块（`radius_size`）；其余键按下时是小圆角。
            borderRadius: BorderRadius.circular(isEquals ? 30 : 8),
          ),
          alignment: Alignment.center,
          child: Text(
            spec.label,
            maxLines: 1,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w400,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

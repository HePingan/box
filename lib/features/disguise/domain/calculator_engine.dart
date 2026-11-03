/// 伪装计算器的表达式内核。
///
/// 为什么要有它：假界面必须**真能算**。只要算错一次、或者随手按几下就卡住，
/// 「这是个计算器」的伪装当场就破了 —— 旁人拿起手机按两下 1+1 得到 3，
/// 比任何痕迹都更能说明这应用有问题。所以这里是一个完整的小型计算器：
/// 输入状态机 + 优先级求值 + 实时预览，纯 Dart、不依赖 Flutter，可单测。
///
/// 运算符在内部一律以显示字符保存（`×` `÷` `−` `+`），求值前才归一化成
/// ASCII —— 这样界面直接 `expression` 就能显示，不需要两套字符串互转，
/// 也就不会出现「显示 + 实际存的是 *」这类只有长时间使用才暴露的错位。
library;

/// 求值失败。`message` 是可以直接显示给用户的中文。
class CalculatorError implements Exception {
  const CalculatorError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 除零的提示文案（与 vivo 计算器一致的口径）。
const String kDivideByZeroMessage = '不能除以零';

/// 表达式残缺（例如 `12+`）时的提示文案。
const String kMalformedMessage = '格式错误';

/// 计算结果。
class CalculatorResult {
  const CalculatorResult.value(this.text) : error = null;
  const CalculatorResult.error(this.error) : text = null;

  /// 成功时的显示文本（已格式化）。
  final String? text;

  /// 失败时的中文提示。
  final String? error;

  bool get isError => error != null;

  /// 无论成败都能直接贴在结果行上的字符串。
  String get display => text ?? error ?? '';
}

/// 一个小型计算器的输入状态机。
///
/// 设计约束（都是为了「看起来就像系统计算器」）：
/// - 一个数字里只有一个小数点；
/// - 连续按运算符时**替换**上一个运算符，而不是报错（系统计算器都这样）；
/// - 表达式为空时按运算符忽略，按 `=` 不产生任何动作；
/// - 结果永不出现 `1.0` 这种尾巴，整数就显示整数。
class CalculatorEngine {
  /// 表达式长度上限。超过就忽略新输入，避免溢出成一个无限长的横条。
  static const int maxExpressionLength = 60;

  /// 单个数字整数部分的位数上限。
  static const int maxNumberLength = 15;

  static const List<String> operators = <String>['+', '−', '×', '÷'];

  String _expression = '';

  /// 当前完整表达式（显示用），例如 `12+3×4`。
  String get expression => _expression;

  bool get isEmpty => _expression.isEmpty;

  /// 最近一次求值后按 `=` 得到的结果；继续输入会被清空。
  ///
  /// 界面用它决定结果行显示什么：有按键过但表达式为空时，系统计算器显示 `0`，
  /// 所以这里是空串，由界面决定占位。
  String _lastResult = '';

  String get lastResult => _lastResult;

  /// 表达式末尾那个正在输入的数字（只含数字与小数点）。
  ///
  /// 伪装解锁靠它：用户输完 PIN 直接按 `=`，此时它正好等于 PIN。
  /// 含小数点或为空时返回空串 —— 口令只可能是纯数字。
  String get trailingNumber {
    // `\.\d*` 而不是 `\.\d+`：正在输入 `0.` 时末尾那个数字是 `0.`，
    // 用 `\.\d+` 会匹配不上，于是 `inputDigit` 把每个后续数字都当成"开始新数字"
    // 而拒收 —— 表现就是「小数点后面按什么都没反应」（这版第一稿的真 bug）。
    final match = RegExp(r'(\d+(?:\.\d*)?)$').firstMatch(_expression);
    return match?.group(1) ?? '';
  }

  void clear() {
    _expression = '';
    _lastResult = '';
  }

  void backspace() {
    if (_expression.isEmpty) return;
    _expression = _expression.substring(0, _expression.length - 1);
  }

  /// 输入一个数字字符（`0`-`9`）。
  bool inputDigit(String digit) {
    if (!RegExp(r'^[0-9]$').hasMatch(digit)) return false;
    if (_expression.length >= maxExpressionLength) return false;

    final trailing = trailingNumber;
    if (trailing.isEmpty) {
      // 表达式为空，或末尾是运算符：开始新数字。
      // 数字前是 `-`（负号）的情况也走这里。
      if (_expression.endsWith('.') || _expression.endsWith(')')) return false;
      _expression += digit;
      _lastResult = '';
      return true;
    }
    // 单个数字过长就不再接收，避免显示溢出。
    final integerPart = trailing.split('.').first;
    if (!trailing.contains('.') && integerPart.length >= maxNumberLength) {
      return false;
    }
    _expression += digit;
    _lastResult = '';
    return true;
  }

  /// 输入小数点。
  bool inputDot() {
    if (_expression.length >= maxExpressionLength) return false;
    final trailing = trailingNumber;
    if (trailing.isEmpty) {
      // 末尾是运算符或空表达式：按 0.x 处理，与系统计算器一致。
      _expression += '0.';
      _lastResult = '';
      return true;
    }
    if (trailing.contains('.')) return false;
    _expression += '.';
    _lastResult = '';
    return true;
  }

  /// 输入运算符 `+` `−` `×` `÷`。
  bool inputOperator(String op) {
    if (!operators.contains(op)) return false;
    if (_expression.isEmpty) return false;
    if (_expression.length >= maxExpressionLength) return false;

    final last = _expression[_expression.length - 1];
    // 末尾是运算符：替换，而不是叠加出 `+-`。末尾是小数点：先补 0。
    if (operators.contains(last)) {
      _expression = _expression.substring(0, _expression.length - 1) + op;
    } else if (last == '.') {
      _expression += '0$op';
    } else {
      _expression += op;
    }
    _lastResult = '';
    return true;
  }

  /// 正负号：翻转末尾那个数字，或把空表达式变成 `-`。
  bool toggleSign() {
    if (_expression.isEmpty) {
      _expression = '-';
      _lastResult = '';
      return true;
    }
    final trailing = trailingNumber;
    if (trailing.isEmpty) {
      // 末尾是运算符：插入负号，`5×` → `5×-`。
      if (_expression.endsWith('-')) {
        _expression = _expression.substring(0, _expression.length - 1);
      } else {
        _expression += '-';
      }
      _lastResult = '';
      return true;
    }
    final start = _expression.length - trailing.length;
    final prefix = _expression.substring(0, start);
    final negated = prefix.endsWith('-')
        ? prefix.substring(0, prefix.length - 1)
        : '$prefix-';
    _expression = '$negated$trailing';
    _lastResult = '';
    return true;
  }

  /// 百分号：把末尾那个数字除以 100（`50+10%` → `50+0.1`）。
  bool percent() {
    final trailing = trailingNumber;
    if (trailing.isEmpty) return false;
    final start = _expression.length - trailing.length;
    final prefix = _expression.substring(0, start);
    final value = double.tryParse(trailing);
    if (value == null) return false;
    _expression = '$prefix${formatNumber(value / 100)}';
    _lastResult = '';
    return true;
  }

  /// 实时预览：表达式可以求值时返回结果文本，否则返回空串。
  String get preview {
    if (_expression.isEmpty) return '';
    final last = _expression[_expression.length - 1];
    if (operators.contains(last) || last == '.' || last == '-') return '';
    final CalculatorResult result = evaluate();
    return result.text ?? '';
  }

  /// 求值。不会修改表达式，`=` 的语义由调用方决定。
  CalculatorResult evaluate() {
    if (_expression.isEmpty) {
      return const CalculatorResult.error(kMalformedMessage);
    }
    try {
      final double value = _evaluateExpression(_expression);
      if (value.isNaN || value.isInfinite) {
        return const CalculatorResult.error(kDivideByZeroMessage);
      }
      return CalculatorResult.value(formatNumber(value));
    } on CalculatorError catch (error) {
      return CalculatorResult.error(error.message);
    }
  }

  /// 按 `=`：算完把表达式换成结果，让用户能接着算（系统计算器的行为）。
  CalculatorResult commit() {
    final result = evaluate();
    if (result.isError) {
      _lastResult = result.error!;
      return result;
    }
    final text = result.text!;
    _expression = text;
    _lastResult = text;
    return result;
  }

  /// 仅供测试：直接置入表达式。
  void debugSetExpression(String expression) {
    _expression = expression;
    _lastResult = '';
  }
}

/// 把 double 格式化成计算器该有的样子：不留 `.0` 尾巴，最多 10 位小数，
/// 超出范围时退回科学计数法。
String formatNumber(double value) {
  if (value == 0) return '0';
  final double rounded = value;
  if (rounded == rounded.roundToDouble() && rounded.abs() < 1e16) {
    return rounded.round().toString();
  }
  var text = rounded.toStringAsFixed(10);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  if (text == '-0') return '0';
  return text;
}

/// 表达式求值（递归下降，支持 `+ − × ÷` 与一元负号）。
double _evaluateExpression(String expression) {
  final normalized = expression
      .replaceAll('×', '*')
      .replaceAll('÷', '/')
      .replaceAll('−', '-')
      .replaceAll(' ', '');
  final parser = _Parser(normalized);
  final value = parser.parseExpression();
  if (!parser.isAtEnd) {
    throw const CalculatorError(kMalformedMessage);
  }
  return value;
}

class _Parser {
  _Parser(this.source);

  final String source;
  int _index = 0;

  bool get isAtEnd => _index >= source.length;

  double parseExpression() {
    var value = parseTerm();
    while (!isAtEnd) {
      final op = source[_index];
      if (op == '+') {
        _index++;
        value += parseTerm();
      } else if (op == '-') {
        _index++;
        value -= parseTerm();
      } else {
        break;
      }
    }
    return value;
  }

  double parseTerm() {
    var value = parseFactor();
    while (!isAtEnd) {
      final op = source[_index];
      if (op == '*') {
        _index++;
        value *= parseFactor();
      } else if (op == '/') {
        _index++;
        final divisor = parseFactor();
        if (divisor == 0) throw const CalculatorError(kDivideByZeroMessage);
        value /= divisor;
      } else {
        break;
      }
    }
    return value;
  }

  double parseFactor() {
    if (isAtEnd) throw const CalculatorError(kMalformedMessage);
    final char = source[_index];
    if (char == '-') {
      _index++;
      return -parseFactor();
    }
    if (char == '+') {
      _index++;
      return parseFactor();
    }
    final start = _index;
    var seenDot = false;
    while (!isAtEnd) {
      final c = source[_index];
      if (c == '.') {
        if (seenDot) throw const CalculatorError(kMalformedMessage);
        seenDot = true;
        _index++;
      } else if (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39) {
        _index++;
      } else {
        break;
      }
    }
    if (_index == start) throw const CalculatorError(kMalformedMessage);
    final text = source.substring(start, _index);
    final value = double.tryParse(text);
    if (value == null) throw const CalculatorError(kMalformedMessage);
    return value;
  }
}

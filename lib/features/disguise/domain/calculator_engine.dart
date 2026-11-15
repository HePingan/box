/// 伪装计算器的表达式内核。
///
/// 为什么要有它：假界面必须**真能算**。只要算错一次、或者随手按几下就卡住，
/// 「这是个计算器」的伪装当场就破了 —— 旁人拿起手机按两下 1+1 得到 3，
/// 比任何痕迹都更能说明这应用有问题。所以这里是一个完整的小型计算器：
/// 输入状态机 + 优先级求值 + 实时预览，纯 Dart、不依赖 Flutter，可单测。
///
/// 运算符在内部一律以显示字符保存（`×` `÷` `−` `π` `√`），求值前才归一化成
/// ASCII —— 这样界面直接 `expression` 就能显示，不需要两套字符串互转，
/// 也就不会出现「显示 + 实际存的是 *」这类只有长时间使用才暴露的错位。
///
/// 键位照着被仿的 vivo 计算器（`com.android.bbkcalculator` 15.6.1.1）的
/// `nex_pad_numeric` / `nex_pad_operator_one_col` 布局来做，所以除了四则运算还得有：
/// 记忆键（mc / m+ / m− / mr）、科学模式那一组函数（sin/cos/tan/反三角、ln、log、
/// √、π、e、括号、乘方、阶乘）以及 Deg/Rad 角度模式。这些在真机上都是**能用**的，
/// 我们只摆个样子的话，旁人一按就露。
library;

import 'dart:math' as math;

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

/// 结果超出可表示范围（真机会显示「超出范围」这类提示）。
const String kOverflowMessage = '数值超出范围';

/// 角度模式。真机计算器顶部的 `Deg`/`Rad` 小字就是这个状态（12sp，`#878787`）。
enum AngleMode { deg, rad }

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

  /// 科学模式的函数键：显示名 -> 追加到表达式里的文本。
  ///
  /// 真机的标签来自 `string/fun_*`（sin / cos / tan / sin-1 / ln / log …），
  /// 引擎侧统一按 `名字(` 追加，求值时由 [_Tokenizer] 认。
  static const List<String> functions = <String>[
    'sin',
    'cos',
    'tan',
    'asin',
    'acos',
    'atan',
    'ln',
    'log',
    '√',
  ];

  String _expression = '';

  /// 当前完整表达式（显示用），例如 `12+3×4`。
  String get expression => _expression;

  bool get isEmpty => _expression.isEmpty;

  AngleMode _angleMode = AngleMode.deg;

  AngleMode get angleMode => _angleMode;

  /// 顶部那个 `Deg`/`Rad` 小字用的文本（真机就是这两个词）。
  String get angleLabel => _angleMode == AngleMode.deg ? 'Deg' : 'Rad';

  void toggleAngleMode() {
    _angleMode = _angleMode == AngleMode.deg ? AngleMode.rad : AngleMode.deg;
  }

  /// 最近一次求值后按 `=` 得到的结果；继续输入会被清空。
  ///
  /// 界面用它决定结果行显示什么：有按键过但表达式为空时，系统计算器显示 `0`，
  /// 所以这里是空串，由界面决定占位。
  String _lastResult = '';

  String get lastResult => _lastResult;

  /// 记忆体（真机的 mc / m+ / m− / mr）。`null` 表示还没存过东西，
  /// 这时按 mr 应该什么都不发生 —— 真机也是这样，不会插一个 0 进去。
  double? _memory;

  bool get hasMemory => _memory != null;

  double? get memory => _memory;

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

  /// 退格。函数名、常量整段删掉，而不是一次删一个字符。
  ///
  /// 理由：`sin(` 逐字符删会先变成 `sin`、`si`、`s` —— 界面上看是「删一下没反应、
  /// 再删一下冒出半个函数名」，真机不是这个手感。
  void backspace() {
    if (_expression.isEmpty) return;
    for (final token in _deletableTokens) {
      if (_expression.endsWith(token)) {
        _expression = _expression.substring(0, _expression.length - token.length);
        _lastResult = '';
        return;
      }
    }
    _expression = _expression.substring(0, _expression.length - 1);
    _lastResult = '';
  }

  /// 退格时按整段识别的词，长的在前（`asin(` 必须先于 `sin(` 判定）。
  static const List<String> _deletableTokens = <String>[
    'asin(',
    'acos(',
    'atan(',
    'sin(',
    'cos(',
    'tan(',
    'log(',
    'ln(',
    '√(',
    'π',
  ];

  /// 输入一个数字字符（`0`-`9`）。
  bool inputDigit(String digit) {
    if (!RegExp(r'^[0-9]$').hasMatch(digit)) return false;
    if (_expression.length >= maxExpressionLength) return false;

    final trailing = trailingNumber;
    if (trailing.isEmpty) {
      // 表达式为空、末尾是运算符、或末尾是 `(`、`π`、`e`、`!` 等：开始新数字。
      if (_expression.endsWith('.')) return false;
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
    } else if (last == '(') {
      // `(` 后面直接按运算符没有意义，忽略。
      return false;
    } else {
      _expression += op;
    }
    _lastResult = '';
    return true;
  }

  /// 乘方 `^`（科学模式）。
  bool inputPower() {
    if (_expression.isEmpty || _expression.length >= maxExpressionLength) {
      return false;
    }
    final last = _expression[_expression.length - 1];
    if (operators.contains(last) || last == '(' || last == '^') return false;
    _expression += '^';
    _lastResult = '';
    return true;
  }

  /// 阶乘 `!`（后缀，科学模式）。
  bool inputFactorial() {
    if (_expression.isEmpty || _expression.length >= maxExpressionLength) {
      return false;
    }
    final last = _expression[_expression.length - 1];
    final canFollow = RegExp(r'[0-9)!πe]').hasMatch(last);
    if (!canFollow) return false;
    _expression += '!';
    _lastResult = '';
    return true;
  }

  /// x²：给末尾那个数加平方（追加 `^2`，求值走乘方，不是自己另算一套）。
  bool inputSquare() => _appendExponent('2');

  /// 1/x：追加 `^(-1)`。写成一元的负一次幂而不是「1÷x」，
  /// 这样 `5^(−1)` 与 `(2+3)^(−1)` 都自动正确，不需要额外的括号逻辑。
  bool inputReciprocal() => _appendExponent('(-1)');

  bool _appendExponent(String exponent) {
    if (_expression.isEmpty || _expression.length >= maxExpressionLength) {
      return false;
    }
    final last = _expression[_expression.length - 1];
    final canFollow = RegExp(r'[0-9)!πe]').hasMatch(last);
    if (!canFollow) return false;
    _expression += '^$exponent';
    _lastResult = '';
    return true;
  }

  /// 函数键：追加 `名字(`（例如 `sin(`）。
  bool inputFunction(String name) {
    if (!functions.contains(name)) return false;
    if (_expression.length + name.length + 1 > maxExpressionLength) return false;
    _expression += '$name(';
    _lastResult = '';
    return true;
  }

  /// 常量 π / e。
  bool inputConstant(String constant) {
    if (constant != 'π' && constant != 'e') return false;
    if (_expression.length >= maxExpressionLength) return false;
    final last = _expression.isEmpty ? '' : _expression[_expression.length - 1];
    // 数字或 `)` 后面直接跟常量是非法表达式，真机会先拒绝（或者补乘号）——
    // 这里选择拒绝，避免出现 `2π` 这种我们不求值的写法。
    if (RegExp(r'[0-9).!πe]').hasMatch(last)) return false;
    _expression += constant;
    _lastResult = '';
    return true;
  }

  /// 括号：按当前括号平衡决定是 `(` 还是 `)`。
  bool inputParen() {
    if (_expression.length >= maxExpressionLength) return false;
    final open = '('.allMatches(_expression).length;
    final close = ')'.allMatches(_expression).length;
    final last = _expression.isEmpty ? '' : _expression[_expression.length - 1];

    final bool canOpen = _expression.isEmpty ||
        operators.contains(last) ||
        last == '(' ||
        last == '^';
    final bool canClose = open > close && !operators.contains(last) && last != '(';

    if (canClose && !canOpen) {
      _expression += ')';
    } else if (canOpen) {
      _expression += '(';
    } else if (canClose) {
      _expression += ')';
    } else {
      return false;
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

  // ——— 记忆键（mc / m+ / m− / mr）———

  /// mc：清空记忆体。
  bool memoryClear() {
    final had = _memory != null;
    _memory = null;
    return had;
  }

  /// m+ / m−：拿当前显示的数值加/减进记忆体。
  ///
  /// 取的是「当前算得出来的值」：表达式能求值就用它，否则退回上一次 `=` 的结果。
  /// 真机的 m+ 也是这个口径（屏幕上没有结果时按它不会报错，只是什么都不加）。
  bool memoryAdd({bool subtract = false}) {
    final value = _currentValue();
    if (value == null) return false;
    final base = _memory ?? 0;
    _memory = subtract ? base - value : base + value;
    return true;
  }

  /// mr：把记忆体的值插进表达式。记忆体是空的时候什么都不做（真机如此）。
  bool memoryRecall() {
    final value = _memory;
    if (value == null) return false;
    if (_expression.length >= maxExpressionLength) return false;
    final last = _expression.isEmpty ? '' : _expression[_expression.length - 1];
    if (RegExp(r'[0-9).!πe]').hasMatch(last)) return false;
    _expression += formatNumber(value);
    _lastResult = '';
    return true;
  }

  /// 当前能代表屏幕的那一个数值（算不出来就是上一次的结果）。
  double? _currentValue() {
    if (_expression.isNotEmpty) {
      final result = evaluate();
      if (!result.isError && result.text != null) {
        return double.tryParse(result.text!);
      }
    }
    return double.tryParse(_lastResult);
  }

  /// 实时预览：表达式可以求值时返回结果文本，否则返回空串。
  String get preview {
    if (_expression.isEmpty) return '';
    final last = _expression[_expression.length - 1];
    if (operators.contains(last) || last == '.' || last == '-') return '';
    if (last == '(' || last == '^') return '';
    final CalculatorResult result = evaluate();
    return result.text ?? '';
  }

  /// 求值。不会修改表达式，`=` 的语义由调用方决定。
  CalculatorResult evaluate() {
    if (_expression.isEmpty) {
      return const CalculatorResult.error(kMalformedMessage);
    }
    try {
      final open = '('.allMatches(_expression).length;
      final close = ')'.allMatches(_expression).length;
      // 括号没配平：真机这时不显示结果（不是报错），交给界面按「预览为空」处理。
      if (open != close) return const CalculatorResult.error(kMalformedMessage);
      final double value = _evaluateExpression(_expression, _angleMode);
      if (value.isNaN) {
        return const CalculatorResult.error(kMalformedMessage);
      }
      if (value.isInfinite) {
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

// ——— 词法 / 语法 ———

/// 表达式求值（递归下降：加减 < 乘除 < 乘方 < 一元负号 < 后缀阶乘 < 原子）。
double _evaluateExpression(String expression, AngleMode mode) {
  final normalized = expression
      .replaceAll('×', '*')
      .replaceAll('÷', '/')
      .replaceAll('−', '-')
      .replaceAll('√', 'sqrt')
      .replaceAll('π', 'pi')
      .replaceAll(' ', '');
  final parser = _Parser(_tokenize(normalized), mode);
  final value = parser.parseExpression();
  if (!parser.isAtEnd) {
    throw const CalculatorError(kMalformedMessage);
  }
  return value;
}

enum _Kind { number, name, operator, lparen, rparen, factorial }

class _Token {
  const _Token(this.kind, this.text, [this.value]);

  final _Kind kind;
  final String text;
  final double? value;

  @override
  String toString() => '${kind.name}:$text';
}

const Set<String> _functionNames = <String>{
  'sin',
  'cos',
  'tan',
  'asin',
  'acos',
  'atan',
  'ln',
  'log',
  'sqrt',
};

List<_Token> _tokenize(String source) {
  final tokens = <_Token>[];
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    final code = c.codeUnitAt(0);
    if (code >= 0x30 && code <= 0x39 || c == '.') {
      final start = i;
      var seenDot = false;
      while (i < source.length) {
        final ch = source[i];
        final cu = ch.codeUnitAt(0);
        if (cu >= 0x30 && cu <= 0x39) {
          i++;
        } else if (ch == '.' && !seenDot) {
          seenDot = true;
          i++;
        } else {
          break;
        }
      }
      final text = source.substring(start, i);
      final value = double.tryParse(text);
      if (value == null) throw const CalculatorError(kMalformedMessage);
      tokens.add(_Token(_Kind.number, text, value));
      continue;
    }
    if (RegExp(r'[a-zA-Z]').hasMatch(c)) {
      final start = i;
      while (i < source.length && RegExp(r'[a-zA-Z]').hasMatch(source[i])) {
        i++;
      }
      final name = source.substring(start, i);
      if (name == 'pi') {
        tokens.add(_Token(_Kind.number, 'π', math.pi));
      } else if (name == 'e') {
        tokens.add(_Token(_Kind.number, 'e', math.e));
      } else if (name == 'sqrt') {
        tokens.add(const _Token(_Kind.name, 'sqrt'));
      } else if (_functionNames.contains(name)) {
        tokens.add(_Token(_Kind.name, name));
      } else {
        throw const CalculatorError(kMalformedMessage);
      }
      continue;
    }
    switch (c) {
      case '+':
      case '-':
      case '*':
      case '/':
      case '^':
        tokens.add(_Token(_Kind.operator, c));
        break;
      case '(':
        tokens.add(const _Token(_Kind.lparen, '('));
        break;
      case ')':
        tokens.add(const _Token(_Kind.rparen, ')'));
        break;
      case '!':
        tokens.add(const _Token(_Kind.factorial, '!'));
        break;
      default:
        throw const CalculatorError(kMalformedMessage);
    }
    i++;
  }
  return tokens;
}

class _Parser {
  _Parser(this.tokens, this.mode);

  final List<_Token> tokens;
  final AngleMode mode;
  int _index = 0;

  bool get isAtEnd => _index >= tokens.length;

  _Token get _current => tokens[_index];

  double parseExpression() {
    var value = parseTerm();
    while (!isAtEnd && _current.kind == _Kind.operator) {
      final op = _current.text;
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
    var value = parseUnary();
    while (!isAtEnd && _current.kind == _Kind.operator) {
      final op = _current.text;
      if (op == '*') {
        _index++;
        value *= parseUnary();
      } else if (op == '/') {
        _index++;
        final divisor = parseUnary();
        if (divisor == 0) throw const CalculatorError(kDivideByZeroMessage);
        value /= divisor;
      } else {
        break;
      }
    }
    return value;
  }

  double parseUnary() {
    if (!isAtEnd && _current.kind == _Kind.operator) {
      final op = _current.text;
      if (op == '-') {
        _index++;
        return -parseUnary();
      }
      if (op == '+') {
        _index++;
        return parseUnary();
      }
    }
    return parsePower();
  }

  double parsePower() {
    final base = parsePostfix();
    if (!isAtEnd && _current.kind == _Kind.operator && _current.text == '^') {
      _index++;
      // 右结合：2^3^2 = 2^(3^2)。
      final exponent = parseUnary();
      final result = math.pow(base, exponent).toDouble();
      if (result.isNaN) throw const CalculatorError(kMalformedMessage);
      return result;
    }
    return base;
  }

  double parsePostfix() {
    var value = parseAtom();
    while (!isAtEnd && _current.kind == _Kind.factorial) {
      _index++;
      value = _factorial(value);
    }
    return value;
  }

  double parseAtom() {
    if (isAtEnd) throw const CalculatorError(kMalformedMessage);
    final token = _current;
    if (token.kind == _Kind.number) {
      _index++;
      return token.value!;
    }
    if (token.kind == _Kind.lparen) {
      _index++;
      final value = parseExpression();
      if (isAtEnd || _current.kind != _Kind.rparen) {
        throw const CalculatorError(kMalformedMessage);
      }
      _index++;
      return value;
    }
    if (token.kind == _Kind.name) {
      _index++;
      // 函数参数允许省略括号：`sin30` 也能算出来（真机都是带括号的写法，
      // 但省略括号时直接报错会让「按了 sin 再按 3 0」这种输入显得很脆）。
      final double argument;
      if (!isAtEnd && _current.kind == _Kind.lparen) {
        _index++;
        argument = parseExpression();
        if (isAtEnd || _current.kind != _Kind.rparen) {
          throw const CalculatorError(kMalformedMessage);
        }
        _index++;
      } else {
        argument = parseUnary();
      }
      return _applyFunction(token.text, argument);
    }
    throw const CalculatorError(kMalformedMessage);
  }

  double _applyFunction(String name, double x) {
    final bool degrees = mode == AngleMode.deg;
    final double radians = degrees ? x * math.pi / 180 : x;
    switch (name) {
      case 'sin':
        return _clean(math.sin(radians));
      case 'cos':
        return _clean(math.cos(radians));
      case 'tan':
        final value = math.tan(radians);
        if (value.abs() > 1e15) throw const CalculatorError(kMalformedMessage);
        return _clean(value);
      case 'asin':
      case 'acos':
      case 'atan':
        if ((name == 'asin' || name == 'acos') && (x < -1 || x > 1)) {
          throw const CalculatorError(kMalformedMessage);
        }
        final value = name == 'asin'
            ? math.asin(x)
            : name == 'acos'
                ? math.acos(x)
                : math.atan(x);
        return degrees ? value * 180 / math.pi : value;
      case 'ln':
        if (x <= 0) throw const CalculatorError(kMalformedMessage);
        return math.log(x);
      case 'log':
        if (x <= 0) throw const CalculatorError(kMalformedMessage);
        return math.log(x) / math.ln10;
      case 'sqrt':
        if (x < 0) throw const CalculatorError(kMalformedMessage);
        return math.sqrt(x);
      default:
        throw const CalculatorError(kMalformedMessage);
    }
  }

  /// 消掉 `sin(180°)` 这种本该是 0 却算出 1.2e-16 的浮点灰。
  double _clean(double value) {
    const double epsilon = 1e-12;
    if (value.abs() < epsilon) return 0;
    final double nearest = value.roundToDouble();
    if ((value - nearest).abs() < epsilon) return nearest;
    return value;
  }

  double _factorial(double value) {
    if (value < 0 || value != value.roundToDouble() || value > 170) {
      throw const CalculatorError(kMalformedMessage);
    }
    var result = 1.0;
    for (var i = 2; i <= value.toInt(); i++) {
      result *= i;
    }
    return result;
  }
}

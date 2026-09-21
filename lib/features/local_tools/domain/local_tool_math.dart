/// 纯本地工具的计算层：不联网、不碰 Flutter、不依赖平台通道。
///
/// 这些能力（科学计算器、单位换算、房贷、进制转换……）本来就是 App 自己
/// 就能算的东西，却因为「没接公开 API」被标成未接线摆在折叠区 —— 用户
/// 被告知「计划中」，其实一行纯函数就能算出来。
///
/// 放这里的都是可在单测里全量覆盖的确定性逻辑；UI 只负责收输入、画结果。
library;

import 'dart:math' as math;

/// 本地工具在计算过程中的可预期错误（输入非法、除零、单位不匹配……）。
///
/// 特意区别于程序缺陷：这些是可以展示给用户的提示文案，UI 直接
/// `catch` 后显示 [message] 即可，不需要当崩溃处理。
class LocalToolError implements Exception {
  const LocalToolError(this.message);

  final String message;

  @override
  String toString() => message;
}

// ───────────────────────────── 科学计算器 ─────────────────────────────

/// 求四则运算表达式：支持 `+ - * / ^`、括号、一元负号、小数。
///
/// 手写递归下降而不是 `eval` —— Dart 没有 eval，也不该为这点需求引入
/// 表达式引擎依赖。
double evalArithmetic(String expr) {
  final s = expr.replaceAll(' ', '');
  if (s.isEmpty) throw const LocalToolError('表达式为空');
  final p = _ExprParser(s);
  final result = p.parseAll();
  if (result.isNaN || result.isInfinite) {
    throw const LocalToolError('计算结果无效');
  }
  return result;
}

/// 递归下降解析器。
///
/// 写成一个类而不是几个闭包，是因为 Dart 的局部函数**不能互相前向引用**
/// （`parseExpr` 调 `parseTerm`、`parseTerm` 又调回 `parseExpr`），
/// 闭包互调在 Dart 里直接编译不过。
class _ExprParser {
  _ExprParser(this.s);

  final String s;
  int pos = 0;

  double parseAll() {
    final v = _expr();
    if (pos != s.length) {
      throw LocalToolError('表达式尾部有多余字符「${s.substring(pos)}」');
    }
    return v;
  }

  double _expr() {
    var left = _term();
    while (pos < s.length && (s[pos] == '+' || s[pos] == '-')) {
      final op = s[pos++];
      final right = _term();
      left = op == '+' ? left + right : left - right;
    }
    return left;
  }

  double _term() {
    var left = _power();
    while (pos < s.length && (s[pos] == '*' || s[pos] == '/')) {
      final op = s[pos++];
      final right = _power();
      if (op == '*') {
        left *= right;
      } else {
        if (right == 0) throw const LocalToolError('除数不能为 0');
        left /= right;
      }
    }
    return left;
  }

  double _power() {
    final base = _unary();
    if (pos < s.length && s[pos] == '^') {
      pos++;
      final exp = _power(); // 右结合
      return _pow(base, exp);
    }
    return base;
  }

  double _unary() {
    if (pos < s.length && s[pos] == '-') {
      pos++;
      return -_unary();
    }
    if (pos < s.length && s[pos] == '+') {
      pos++;
      return _unary();
    }
    return _atom();
  }

  double _atom() {
    if (pos >= s.length) throw const LocalToolError('表达式不完整');
    if (s[pos] == '(') {
      pos++;
      final v = _expr();
      if (pos >= s.length || s[pos] != ')') {
        throw const LocalToolError('括号不匹配');
      }
      pos++;
      return v;
    }
    final start = pos;
    while (pos < s.length && (_isDigit(s[pos]) || s[pos] == '.')) {
      pos++;
    }
    if (start == pos) {
      throw LocalToolError('无法识别的字符「${s[pos]}」');
    }
    final v = double.tryParse(s.substring(start, pos));
    if (v == null) throw const LocalToolError('数字格式错误');
    return v;
  }
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

double _pow(double base, double exp) {
  if (exp == exp.roundToDouble() && exp >= 0 && exp < 1000) {
    var r = 1.0;
    for (var i = 0; i < exp.toInt(); i++) {
      r *= base;
    }
    return r;
  }
  // 非整数指数走 exp/ln（dart:math）
  return _mathPow(base, exp);
}

// ───────────────────────────── 单位换算 ─────────────────────────────

/// 单位所属类别。跨类换算没有意义，直接报错而不是给个假数字。
enum UnitCategory { length, weight, temperature, area, volume }

/// 换算到基准单位的系数；温度单独处理（有偏移量，不是纯比例）。
const Map<String, double> _lengthFactors = {
  'mm': 0.001,
  'cm': 0.01,
  'm': 1,
  'km': 1000,
  'inch': 0.0254,
  'ft': 0.3048,
  'mile': 1609.344,
  '里': 500,
  '尺': 1 / 3,
  '寸': 0.1 / 3,
};

const Map<String, double> _weightFactors = {
  'mg': 0.000001,
  'g': 0.001,
  'kg': 1,
  't': 1000,
  'jin': 0.5, // 市斤
  'liang': 0.05, // 市两
  'lb': 0.45359237,
  'oz': 0.028349523125,
};

const Map<String, double> _areaFactors = {
  'm2': 1,
  'cm2': 0.0001,
  'km2': 1000000,
  '亩': 666.6666666666666,
  'ha': 10000,
  'ft2': 0.09290304,
};

const Map<String, double> _volumeFactors = {
  'ml': 0.001,
  'l': 1,
  'm3': 1000,
  'gal': 3.785411784,
};

Map<String, double> _factorTableFor(UnitCategory c) => switch (c) {
      UnitCategory.length => _lengthFactors,
      UnitCategory.weight => _weightFactors,
      UnitCategory.temperature => const {},
      UnitCategory.area => _areaFactors,
      UnitCategory.volume => _volumeFactors,
    };

/// 某类别下可选的单位（UI 下拉用）。
List<String> unitsOf(UnitCategory c) => switch (c) {
      UnitCategory.length => _lengthFactors.keys.toList(),
      UnitCategory.weight => _weightFactors.keys.toList(),
      UnitCategory.temperature => const ['c', 'f', 'k'],
      UnitCategory.area => _areaFactors.keys.toList(),
      UnitCategory.volume => _volumeFactors.keys.toList(),
    };

double convertUnit(double value, String from, String to, UnitCategory category) {
  if (from == to) return value;

  if (category == UnitCategory.temperature) {
    const valid = {'c', 'f', 'k'};
    if (!valid.contains(from) || !valid.contains(to)) {
      throw LocalToolError('温度单位「$from → $to」不支持');
    }
    final celsius = switch (from) {
      'c' => value,
      'f' => (value - 32) * 5 / 9,
      'k' => value - 273.15,
      _ => throw LocalToolError('温度单位「$from」不支持'),
    };
    return switch (to) {
      'c' => celsius,
      'f' => celsius * 9 / 5 + 32,
      'k' => celsius + 273.15,
      _ => throw LocalToolError('温度单位「$to」不支持'),
    };
  }

  final table = _factorTableFor(category);
  final f = table[from];
  final t = table[to];
  if (f == null) throw LocalToolError('单位「$from」不属于当前类别');
  if (t == null) throw LocalToolError('单位「$to」不属于当前类别');
  return value * f / t;
}

// ───────────────────────────── BMI ─────────────────────────────

/// BMI = 体重(kg) / 身高(m)²。身高单位是**厘米**（用户输入习惯）。
double bmiValue(double weightKg, double heightCm) {
  if (weightKg <= 0) throw const LocalToolError('体重必须大于 0');
  if (heightCm <= 0) throw const LocalToolError('身高必须大于 0');
  final m = heightCm / 100;
  return weightKg / (m * m);
}

/// 中国成人 BMI 分级：<18.5 偏瘦 / 18.5–23.9 正常 / 24–27.9 超重 / ≥28 肥胖。
String bmiCategory(double bmi) {
  if (bmi < 18.5) return '偏瘦';
  if (bmi < 24) return '正常';
  if (bmi < 28) return '超重';
  return '肥胖';
}

// ───────────────────────────── 房贷 ─────────────────────────────

/// 等额本息还款计划。
class MortgageEqualInstallmentResult {
  const MortgageEqualInstallmentResult({
    required this.monthlyPayment,
    required this.totalPayment,
    required this.totalInterest,
  });

  final double monthlyPayment;
  final double totalPayment;
  final double totalInterest;
}

/// 等额本金还款计划。
class MortgageEqualPrincipalResult {
  const MortgageEqualPrincipalResult({
    required this.principalPerMonth,
    required this.firstMonthPayment,
    required this.lastMonthPayment,
    required this.totalPayment,
    required this.totalInterest,
  });

  final double principalPerMonth;
  final double firstMonthPayment;
  final double lastMonthPayment;
  final double totalPayment;
  final double totalInterest;
}

/// 等额本息：每月还款额固定。
///
/// `M = P·i·(1+i)^n / ((1+i)^n − 1)`，`i` 是月利率。零利率时退化成
/// 本金均摊 —— 公式的分母会变成 0，所以必须单独分支。
MortgageEqualInstallmentResult mortgageEqualInstallment({
  required double principal,
  required double annualRatePercent,
  required int months,
}) {
  if (principal <= 0) throw const LocalToolError('贷款金额必须大于 0');
  if (months <= 0) throw const LocalToolError('贷款期数必须大于 0');
  if (annualRatePercent < 0) throw const LocalToolError('利率不能为负');

  final i = annualRatePercent / 100 / 12;
  final double monthly;
  if (i == 0) {
    monthly = principal / months;
  } else {
    final growth = _pow(1 + i, months.toDouble());
    monthly = principal * i * growth / (growth - 1);
  }
  final total = monthly * months;
  return MortgageEqualInstallmentResult(
    monthlyPayment: monthly,
    totalPayment: total,
    totalInterest: total - principal,
  );
}

/// 等额本金：每月还的本金固定，利息递减，所以首月最高、末月最低。
MortgageEqualPrincipalResult mortgageEqualPrincipal({
  required double principal,
  required double annualRatePercent,
  required int months,
}) {
  if (principal <= 0) throw const LocalToolError('贷款金额必须大于 0');
  if (months <= 0) throw const LocalToolError('贷款期数必须大于 0');
  if (annualRatePercent < 0) throw const LocalToolError('利率不能为负');

  final perMonth = principal / months;
  final monthlyRate = annualRatePercent / 100 / 12;
  final first = perMonth + principal * monthlyRate;
  final last = perMonth + perMonth * monthlyRate;
  // 利息总额 = 月利率 · 本金 · (n+1)/2
  final totalInterest = monthlyRate * principal * (months + 1) / 2;
  return MortgageEqualPrincipalResult(
    principalPerMonth: perMonth,
    firstMonthPayment: first,
    lastMonthPayment: last,
    totalPayment: principal + totalInterest,
    totalInterest: totalInterest,
  );
}

// ───────────────────────────── 日期 ─────────────────────────────

/// 两个日期相差的天数（`to - from`，可负）。按自然日算，忽略时分秒。
int daysBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// 日期加减天数（自动处理跨月跨年）。
DateTime addDays(DateTime base, int days) {
  final d = DateTime(base.year, base.month, base.day);
  return DateTime(d.year, d.month, d.day + days);
}

bool isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

// ───────────────────────────── 时间戳 ─────────────────────────────

/// Unix 时间戳（秒）→ `yyyy-MM-dd HH:mm:ss`。
///
/// [utc] 为 true 时按 UTC 输出 —— 测试要确定性，不能跟着机器时区变。
String formatTimestamp(int seconds, {bool utc = false}) {
  final t = DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000,
    isUtc: utc,
  );
  String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
  return '${p(t.year, 4)}-${p(t.month)}-${p(t.day)} '
      '${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
}

/// `yyyy-MM-dd HH:mm:ss`（或 `yyyy-MM-dd`）→ Unix 时间戳（秒）。
int parseTimestamp(String text, {bool utc = false}) {
  final m = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?$',
  ).firstMatch(text.trim());
  if (m == null) throw const LocalToolError('时间格式应为 yyyy-MM-dd HH:mm:ss');
  final d = utc
      ? DateTime.utc(
          int.parse(m[1]!),
          int.parse(m[2]!),
          int.parse(m[3]!),
          int.parse(m[4] ?? '0'),
          int.parse(m[5] ?? '0'),
          int.parse(m[6] ?? '0'),
        )
      : DateTime(
          int.parse(m[1]!),
          int.parse(m[2]!),
          int.parse(m[3]!),
          int.parse(m[4] ?? '0'),
          int.parse(m[5] ?? '0'),
          int.parse(m[6] ?? '0'),
        );
  return d.millisecondsSinceEpoch ~/ 1000;
}

/// 把可能是毫秒（13 位）的时间戳统一成秒。
///
/// 用户从别处复制时间戳时常混用两种单位，直接按秒解析会显示 1970 年。
int normalizeTimestampToSeconds(int raw) =>
    raw.abs() >= 100000000000 ? raw ~/ 1000 : raw;

// ───────────────────────────── 进制转换 ─────────────────────────────

/// 任意进制（2–36）之间转换。大小写不敏感，输出统一小写。
String convertRadix(String input, int fromRadix, int toRadix) {
  if (fromRadix < 2 || fromRadix > 36) {
    throw const LocalToolError('来源进制需在 2–36 之间');
  }
  if (toRadix < 2 || toRadix > 36) {
    throw const LocalToolError('目标进制需在 2–36 之间');
  }
  final s = input.trim().toLowerCase();
  if (s.isEmpty) throw const LocalToolError('请输入要转换的数字');

  var negative = false;
  var body = s;
  if (body.startsWith('-')) {
    negative = true;
    body = body.substring(1);
  }
  if (body.isEmpty) throw const LocalToolError('请输入要转换的数字');

  var value = BigInt.zero;
  final radix = BigInt.from(fromRadix);
  for (final ch in body.split('')) {
    final d = _digitValue(ch);
    if (d < 0 || d >= fromRadix) {
      throw LocalToolError('「$ch」不是 $fromRadix 进制的合法数字');
    }
    value = value * radix + BigInt.from(d);
  }

  if (value == BigInt.zero) return '0';
  final out = value.toRadixString(toRadix);
  return negative ? '-$out' : out;
}

int _digitValue(String ch) {
  final c = ch.codeUnitAt(0);
  if (c >= 0x30 && c <= 0x39) return c - 0x30; // 0-9
  if (c >= 0x61 && c <= 0x7a) return c - 0x61 + 10; // a-z
  return -1;
}

// ───────────────────────────── 大小写 ─────────────────────────────

String toUpperCaseText(String s) => s.toUpperCase();
String toLowerCaseText(String s) => s.toLowerCase();

/// 每个单词首字母大写，其余小写。
///
/// 用 `splitMapJoin` 而不是 `split(...).map(...).join()` —— 后者会把
/// 分隔符（空格）丢掉，`'hello world'` 变成 `'HelloWorld'`。
String toTitleCase(String s) =>
    s.splitMapJoin(RegExp(r'\s+'), onMatch: (m) => m[0]!, onNonMatch: (w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    });

// ───────────────────────────── 随机密码 ─────────────────────────────

const String _kLower = 'abcdefghijklmnopqrstuvwxyz';
const String _kUpper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const String _kDigits = '0123456789';
const String _kSymbols = r'!@#$%^&*()_+-=[]{}';

/// 生成随机密码。
///
/// [seed] 只给测试用 —— 传了就用可复现的线性同余发生器，不传走
/// `Random.secure()`（真实随机）。这样既保证生产不可预测，又让
/// 「同种子同结果」这类断言可以单测。
String generatePassword({
  int length = 16,
  bool symbols = false,
  bool digits = true,
  int? seed,
}) {
  if (length <= 0 || length > 128) {
    throw const LocalToolError('密码长度需在 1–128 之间');
  }
  final pool = StringBuffer(_kLower)..write(_kUpper);
  if (digits) pool.write(_kDigits);
  if (symbols) pool.write(_kSymbols);
  final chars = pool.toString();

  final rand = seed == null ? _secureRandom : _Lcg(seed);

  // 先各取一个必含字符，保证「勾了数字却不含数字」这种反直觉结果不出现；
  // 不足长度再随机补。最后打乱，否则前几位总是固定的类别顺序。
  final out = <String>[];
  if (length >= 2) {
    out.add(_kLower[rand.nextInt(_kLower.length)]);
    out.add(_kUpper[rand.nextInt(_kUpper.length)]);
  }
  if (digits && out.length < length) {
    out.add(_kDigits[rand.nextInt(_kDigits.length)]);
  }
  if (symbols && out.length < length) {
    out.add(_kSymbols[rand.nextInt(_kSymbols.length)]);
  }
  while (out.length < length) {
    out.add(chars[rand.nextInt(chars.length)]);
  }
  for (var i = out.length - 1; i > 0; i--) {
    final j = rand.nextInt(i + 1);
    final t = out[i];
    out[i] = out[j];
    out[j] = t;
  }
  return out.join();
}

/// 密码学安全随机源（生产路径）。
///
/// 只有 `seed == null`（真实生成密码）时才用它 —— 结果不可复现，测试
/// 一律走 [_Lcg]。
final _RandomSource _secureRandom = _SecureRandomSource();

/// 随机源统一接口：生产走 `Random.secure()`，测试走可复现的 LCG。
abstract class _RandomSource {
  int nextInt(int max);
}

class _SecureRandomSource implements _RandomSource {
  final math.Random _r = math.Random.secure();

  @override
  int nextInt(int max) => _r.nextInt(max);
}

/// 可复现的线性同余发生器（仅测试用，**不可用于生产密码**）。
class _Lcg implements _RandomSource {
  _Lcg(int seed) : _s = seed & 0x7fffffff;

  int _s;

  @override
  int nextInt(int max) {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s % max;
  }
}

// ───────────────────────────── 亲戚称呼 ─────────────────────────────

/// 从「我」出发的亲属路径 → 称呼。
///
/// 路径元素是每一步的关系（`爸爸`/`妈妈`/`哥哥`/`妻子`……）。查表实现：
/// 常见路径直接命中；未收录的长路径走兜底而不是崩溃 —— 亲戚链条可以有
/// 无穷长，硬编码表不可能穷尽。
String relationTitle(List<String> path) {
  if (path.isEmpty) return '自己';
  final key = path.join('');
  final hit = _kRelations[key];
  if (hit != null) return hit;

  // 兜底：先按「配偶 + 兄弟姐妹」这类两步组合拆一次，仍然没有就给
  // 一个明确的、不误导的说明，而不是瞎猜一个称呼。
  if (path.length > 2) {
    final tail = path.sublist(path.length - 2).join('');
    final head = path.sublist(0, path.length - 2).join('');
    final tailHit = _kRelations[tail];
    if (tailHit != null && _kRelations.containsKey(head)) {
      return '${_kRelations[head]}的$tailHit';
    }
  }
  for (var i = path.length - 1; i >= 1; i--) {
    final head = path.sublist(0, i).join('');
    final tail = path.sublist(i).join('');
    final h = _kRelations[head];
    final t = _kRelations[tail];
    if (h != null && t != null) return '$h的$t';
  }
  return '较远的亲属（未收录该组合）';
}

const Map<String, String> _kRelations = {
  // 一代
  '爸爸': '爸爸',
  '妈妈': '妈妈',
  '哥哥': '哥哥',
  '弟弟': '弟弟',
  '姐姐': '姐姐',
  '妹妹': '妹妹',
  '丈夫': '丈夫',
  '妻子': '妻子',
  '儿子': '儿子',
  '女儿': '女儿',
  // 祖辈
  '爸爸爸爸': '爷爷',
  '爸爸妈妈': '奶奶',
  '妈妈爸爸': '外公',
  '妈妈妈妈': '外婆',
  // 孙辈
  '儿子儿子': '孙子',
  '儿子女儿': '孙女',
  '女儿儿子': '外孙',
  '女儿女儿': '外孙女',
  // 父母的兄弟姐妹（父系）
  '爸爸哥哥': '伯父',
  '爸爸弟弟': '叔叔',
  '爸爸姐姐': '姑妈',
  '爸爸妹妹': '小姑',
  // 父母的兄弟姐妹（母系）
  '妈妈哥哥': '舅舅',
  '妈妈弟弟': '舅舅',
  '妈妈姐姐': '姨妈',
  '妈妈妹妹': '小姨',
  // 同辈配偶
  '哥哥妻子': '嫂子',
  '弟弟妻子': '弟媳',
  '姐姐丈夫': '姐夫',
  '妹妹丈夫': '妹夫',
  // 兄弟姐妹的子女
  '哥哥儿子': '侄子',
  '哥哥女儿': '侄女',
  '弟弟儿子': '侄子',
  '弟弟女儿': '侄女',
  '姐姐儿子': '外甥',
  '姐姐女儿': '外甥女',
  '妹妹儿子': '外甥',
  '妹妹女儿': '外甥女',
  // 子女的配偶
  '儿子妻子': '儿媳',
  '女儿丈夫': '女婿',
  // 父母的兄弟姐妹的子女（堂/表）
  '爸爸哥哥儿子': '堂兄弟',
  '爸爸哥哥女儿': '堂姐妹',
  '爸爸弟弟儿子': '堂兄弟',
  '爸爸弟弟女儿': '堂姐妹',
  '妈妈哥哥儿子': '表哥',
  '妈妈哥哥女儿': '表姐',
  '妈妈姐姐儿子': '表哥',
  '妈妈姐姐女儿': '表姐',
  // 配偶的父母
  '妻子爸爸': '岳父',
  '妻子妈妈': '岳母',
  '丈夫爸爸': '公公',
  '丈夫妈妈': '婆婆',
  // 子女的子女的称呼（叔伯视角）
  '爸爸儿子': '兄弟',
  '爸爸女儿': '姐妹',
  '妈妈儿子': '兄弟',
  '妈妈女儿': '姐妹',
};

// dart:math 的 pow，包一层以保持调用点简短。
double _mathPow(double a, double b) => math.pow(a, b).toDouble();

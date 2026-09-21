/// 批次 3 的纯本地逻辑：随机数、摩斯密码、时钟/秒表/计时器格式化、
/// 刻度尺换算、坏点检测色板。
///
/// 刻意**不包含**指南针 / 水平仪 / 分贝仪 —— 那三个要 `sensors_plus`
/// 与麦克风权限（新依赖 + 真机权限弹窗），等拍板再单独做。
library;

import 'dart:math' as math;

class DeviceToolError implements Exception {
  const DeviceToolError(this.message);

  final String message;

  @override
  String toString() => message;
}

// ────────────────────────────── 随机数 ──────────────────────────────

/// 生成 [count] 个 `[min, max]` 闭区间内的整数。
///
/// [seed] 给了就复现（测试用），不给就走 `Random.secure()`。
/// [unique] 为真时保证不重复；若取值范围比 [count] 小则明确报错 ——
/// 静默返回不足个数会让人以为拿到了想要的量。
List<int> randomInts({
  required int min,
  required int max,
  required int count,
  int? seed,
  bool unique = false,
}) {
  if (min > max) {
    throw DeviceToolError('最小值 $min 不能大于最大值 $max');
  }
  if (count <= 0) {
    throw const DeviceToolError('生成个数要大于 0');
  }
  final span = max - min + 1;
  if (unique && count > span) {
    throw DeviceToolError(
      '$min~$max 之间只有 $span 个不同的数，凑不出 $count 个不重复的',
    );
  }

  final rnd = seed == null ? math.Random.secure() : math.Random(seed);
  if (!unique) {
    return List<int>.generate(count, (_) => min + rnd.nextInt(span));
  }

  // 不重复：小区间直接洗牌取前 count，避免「抽到重复就重抽」的死循环风险。
  final pool = List<int>.generate(span, (i) => min + i);
  pool.shuffle(rnd);
  return pool.take(count).toList();
}

// ───────────────────────────── 摩斯密码 ─────────────────────────────

const Map<String, String> _morseTable = {
  'A': '.-', 'B': '-...', 'C': '-.-.', 'D': '-..', 'E': '.', 'F': '..-.',
  'G': '--.', 'H': '....', 'I': '..', 'J': '.---', 'K': '-.-', 'L': '.-..',
  'M': '--', 'N': '-.', 'O': '---', 'P': '.--.', 'Q': '--.-', 'R': '.-.',
  'S': '...', 'T': '-', 'U': '..-', 'V': '...-', 'W': '.--', 'X': '-..-',
  'Y': '-.--', 'Z': '--..',
  '0': '-----', '1': '.----', '2': '..---', '3': '...--', '4': '....-',
  '5': '.....', '6': '-....', '7': '--...', '8': '---..', '9': '----.',
};

final Map<String, String> _morseReverse = {
  for (final e in _morseTable.entries) e.value: e.key,
};

/// 文本 → 摩斯密码。字母间空格，词间 ` / `。
///
/// 遇到编码表里没有的字符（比如中文）**直接报错**，不静默跳过 ——
/// 否则用户以为翻译成功了，实际丢了一半内容。
String textToMorse(String input) {
  final s = input.trim().toUpperCase();
  if (s.isEmpty) throw const DeviceToolError('请输入要转换的内容');

  final words = <String>[];
  for (final word in s.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final codes = <String>[];
    for (final ch in word.split('')) {
      final code = _morseTable[ch];
      if (code == null) {
        throw DeviceToolError('「$ch」没有对应的摩斯码（目前只支持字母和数字）');
      }
      codes.add(code);
    }
    words.add(codes.join(' '));
  }
  return words.join(' / ');
}

/// 摩斯密码 → 文本。接受 `.`/`-` 与空格、`/` 分隔。
String morseToText(String input) {
  final s = input.trim();
  if (s.isEmpty) throw const DeviceToolError('请输入摩斯密码');
  if (!RegExp(r'^[.\-\s/]+$').hasMatch(s)) {
    throw const DeviceToolError('摩斯密码只能由 . - 空格和 / 组成');
  }

  final words = <String>[];
  for (final word in s.split('/')) {
    final letters = <String>[];
    for (final code in word.trim().split(RegExp(r'\s+'))) {
      if (code.isEmpty) continue;
      final ch = _morseReverse[code];
      if (ch == null) throw DeviceToolError('「$code」不是有效的摩斯码');
      letters.add(ch);
    }
    if (letters.isNotEmpty) words.add(letters.join());
  }
  return words.join(' ');
}

// ─────────────────────────────── 时钟 ───────────────────────────────

String _two(int v) => v.toString().padLeft(2, '0');

/// `HH:mm:ss`（24 小时制）。
String formatClock(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

/// `2026年9月12日 星期六`
String formatClockDate(DateTime t) {
  const week = ['一', '二', '三', '四', '五', '六', '日'];
  return '${t.year}年${t.month}月${t.day}日 星期${week[t.weekday - 1]}';
}

// ────────────────────────────── 秒表 ──────────────────────────────

/// `mm:ss.cc`；超过一小时自动升成 `hh:mm:ss.cc`。
String formatStopwatch(Duration d) {
  final neg = d.isNegative;
  final abs = neg ? -d : d;
  final h = abs.inHours;
  final m = abs.inMinutes % 60;
  final s = abs.inSeconds % 60;
  final cs = (abs.inMilliseconds % 1000) ~/ 10;
  final body = h > 0
      ? '${_two(h)}:${_two(m)}:${_two(s)}.${_two(cs)}'
      : '${_two(m)}:${_two(s)}.${_two(cs)}';
  return neg ? '-$body' : body;
}

/// 一次计次：显示总时间编号 + 与上一次的差值。
class LapEntry {
  const LapEntry({
    required this.label,
    required this.total,
    required this.delta,
  });

  final String label;
  final Duration total;
  final Duration delta;
}

/// 把累计时间点列表转成计次列表（差值 = 本段 - 上一段）。
List<LapEntry> lapDiffs(List<Duration> totals) {
  final out = <LapEntry>[];
  Duration prev = Duration.zero;
  for (var i = 0; i < totals.length; i++) {
    out.add(
      LapEntry(
        label: '第 ${i + 1} 次',
        total: totals[i],
        delta: totals[i] - prev,
      ),
    );
    prev = totals[i];
  }
  return out;
}

// ───────────────────────────── 倒计时 ─────────────────────────────

/// `mm:ss`（超过一小时给 `h:mm:ss`）。负数钳到 0，不显示负号。
String formatCountdown(Duration d) {
  final abs = d.isNegative ? Duration.zero : d;
  final h = abs.inHours;
  final m = abs.inMinutes % 60;
  final s = abs.inSeconds % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
}

/// 解析 `90`（秒）或 `01:30`（分:秒）或 `1:02:03`。
Duration parseCountdown(String input) {
  final s = input.trim();
  if (s.isEmpty) throw const DeviceToolError('请输入倒计时时长');

  final parts = s.split(':');
  if (parts.length > 3) {
    throw const DeviceToolError('格式最多是 时:分:秒');
  }
  final nums = <int>[];
  for (final p in parts) {
    final v = int.tryParse(p.trim());
    if (v == null || v < 0) {
      throw DeviceToolError('「$p」不是有效的数字');
    }
    nums.add(v);
  }
  // 分、秒都必须在 0~59（单独一个数时按秒算，不限 59）。
  for (var i = 1; i < nums.length; i++) {
    if (nums[i] > 59) {
      throw DeviceToolError('分和秒要在 0~59 之间，现在是 ${nums[i]}');
    }
  }

  final secs = switch (nums.length) {
    1 => nums[0],
    2 => nums[0] * 60 + nums[1],
    _ => nums[0] * 3600 + nums[1] * 60 + nums[2],
  };
  if (secs == 0) throw const DeviceToolError('倒计时时长要大于 0');
  return Duration(seconds: secs);
}

// ────────────────────────────── 刻度尺 ──────────────────────────────

/// 逻辑像素按屏幕 dpi 换算成毫米。
///
/// dpi 来自 `MediaQuery.devicePixelRatio` 与平台上报的物理密度；
/// 没有可靠 dpi 时明确报错，而不是除零或返回一个假精度值。
double pxToMillimeters(double px, double dpi) {
  if (dpi <= 0) {
    throw const DeviceToolError('拿不到屏幕密度，没法换算成真实尺寸');
  }
  return px / dpi * 25.4;
}

double mmToCm(double mm) => mm / 10;

// ─────────────────────────── 坏点检测色板 ───────────────────────────

/// 坏点检测用的纯色序列（ARGB）。首尾是黑/白 —— 亮/暗坏点各一轮就能看出来。
const List<int> deadPixelColors = [
  0xFF000000, // 黑：亮点（永远亮的像素）最明显
  0xFFFFFFFF, // 白：暗点（永远黑的像素）最明显
  0xFFFF0000, // 红
  0xFF00FF00, // 绿
  0xFF0000FF, // 蓝
];


// ─────────────────────── 屏幕物理尺寸（刻度尺精度） ───────────────────────

/// 与 `MainActivity.SCREEN_METRICS_CHANNEL` 一一对应。
const String kScreenMetricsChannel = 'top.hpa888.box/screen_metrics';

/// 从平台读到的真实屏幕参数。
class ScreenMetrics {
  const ScreenMetrics({
    required this.widthPx,
    required this.heightPx,
    required this.xdpi,
    required this.ydpi,
    required this.densityDpi,
  });

  final double widthPx;
  final double heightPx;
  final double xdpi;
  final double ydpi;
  final int densityDpi;

  /// 物理尺寸是否可信。
  ///
  /// 有厂商（尤其部分国产 ROM / 折叠屏）把 xdpi 写成一个约等于
  /// `densityDpi` 的整数（如 420.0），那不是真实物理 dpi，用它量长度会明显偏大。
  /// 判据：xdpi 与 densityDpi 完全相等、或落在 densityDpi±1 内，视为可疑。
  bool get isDpiTrustworthy {
    final suspicious = (xdpi - densityDpi).abs() <= 1.0;
    return !suspicious && xdpi > 0 && ydpi > 0;
  }

  @override
  String toString() => 'ScreenMetrics(${widthPx}x$heightPx, '
      'xdpi=$xdpi, ydpi=$ydpi, densityDpi=$densityDpi)';
}

/// 用真实 dpi 把物理像素换算成毫米。
///
/// 与 `pxToMillimeters` 的区别：那个用 `devicePixelRatio * 160` 估算，
/// 这是用平台报的 xdpi。刻度尺应该优先用这个。
double pxToMillimetersWithDpi(double px, double dpi) {
  if (dpi <= 0) {
    throw const DeviceToolError('dpi 必须大于 0');
  }
  return px / dpi * 25.4;
}

/// 选一个可用的 dpi：优先真实 xdpi，不可信时退回估算值。
///
/// 返回 `(dpi, isReal)` —— `isReal=false` 时 UI 要显式标注「估算」，
/// 不能让用户以为是精确值。
({double dpi, bool isReal}) resolveDpi({
  ScreenMetrics? metrics,
  required double fallbackDpr,
}) {
  if (metrics != null && metrics.isDpiTrustworthy) {
    return (dpi: metrics.xdpi, isReal: true);
  }
  return (dpi: fallbackDpr * 160, isReal: false);
}

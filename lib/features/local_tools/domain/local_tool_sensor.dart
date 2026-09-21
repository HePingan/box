/// 批次 4 的纯计算部分：指南针方位、水平仪倾角、分贝换算。
///
/// **分层理由**：`sensors_plus` / `record` 只有在真机上才吐数据，单测里
/// 拿不到流。所以把「原始传感器读数 → 显示值」这段数学单独抽出来放这里，
/// 用注入的假读数全量测；插件那一层只负责「把流接进来」，逻辑为零 ——
/// 这样真机上出偏差时，能立刻判断是数学错了还是硬件/校准问题。
library;

import 'dart:math' as math;

class SensorToolError implements Exception {
  const SensorToolError(this.message);

  final String message;

  @override
  String toString() => message;
}

// ───────────────────────────── 指南针 ─────────────────────────────

/// 磁力计三轴 → 方位角（度，0=正北，顺时针 0~360）。
///
/// 算法：水平面上 `atan2(y, x)`。注意 Android 的磁力计 y 轴指向屏幕上方，
/// 而屏幕坐标系里「北」要按 `atan2(-y, x)` 取，否则东西会镜像。
double headingFromMagnetometer({
  required double x,
  required double y,
}) {
  if (x == 0 && y == 0) {
    throw const SensorToolError('磁场读数为零，可能附近有强磁干扰');
  }
  var deg = math.atan2(x, y) * 180 / math.pi;
  if (deg < 0) deg += 360;
  return deg;
}

/// 方位角 → 八方位中文名。
String headingLabel(double degrees) {
  const names = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
  final d = ((degrees % 360) + 360) % 360;
  // 每个方位占 45°，北在 ±22.5° 之间。
  final idx = (((d + 22.5) % 360) ~/ 45) % 8;
  return names[idx];
}

// ───────────────────────────── 水平仪 ─────────────────────────────

/// 加速度计读数 → 相对水平面的两个倾角（度）。
///
/// `pitch` 是前后倾（绕 x 轴），`roll` 是左右倾（绕 y 轴）。
/// 手机平放时 z ≈ 9.81、x ≈ y ≈ 0，两角都接近 0 —— 这就是「水平」。
({double pitch, double roll}) tiltFromAccelerometer({
  required double x,
  required double y,
  required double z,
}) {
  final norm = math.sqrt(x * x + y * y + z * z);
  if (norm == 0) {
    throw const SensorToolError('加速度读数为零，传感器可能没在采样');
  }
  final pitch = math.asin((-x / norm).clamp(-1.0, 1.0)) * 180 / math.pi;
  final roll = math.asin((y / norm).clamp(-1.0, 1.0)) * 180 / math.pi;
  return (pitch: pitch, roll: roll);
}

/// 双轴倾角 → 气泡相对圆心的偏移量（归一化到 -1~1）。
///
/// 用两个 `sin` 是为了让「倾斜到 90° 时气泡贴边」；直接线性映射会在
/// 大角度下过冲。
({double dx, double dy}) bubbleOffset({
  required double pitch,
  required double roll,
  double maxDegrees = 15,
}) {
  if (maxDegrees <= 0) {
    throw const SensorToolError('量程要大于 0');
  }
  double map(double deg) {
    final r = (deg / maxDegrees).clamp(-1.0, 1.0);
    // 轻度非线性：小角度更灵敏（±1° 就能看出气泡动），大角度仍收敛到边。
    return r * (2 - r.abs()) * 0.5 + r * 0.5;
  }

  return (dx: map(roll), dy: map(pitch));
}

/// 是否已在水平范围内（默认 ±0.5°）。
bool isLevel({
  required double pitch,
  required double roll,
  double tolerance = 0.5,
}) =>
    pitch.abs() <= tolerance && roll.abs() <= tolerance;

// ───────────────────────────── 分贝仪 ─────────────────────────────

/// 线性振幅（0~1）→ 分贝。
///
/// `db = 20 * log10(amplitude)`，再加 [offset] 把手机的相对刻度平移到一个
/// 大致贴近真实声压级的范围。**这是估算值，不是校准过的声压级** ——
/// 手机麦克风没有绝对标定，不同机型差 10dB 以上是常事。
double amplitudeToDb(double amplitude, {double offset = 0}) {
  if (amplitude < 0) {
    throw const SensorToolError('振幅不能是负数');
  }
  if (amplitude == 0) return offset > 0 ? offset - 60 : -60;
  return 20 * math.log(amplitude) / math.ln10 + offset;
}

/// 分贝 → 通俗描述。
String dbLabel(double db) {
  if (db < 30) return '很安静（图书馆）';
  if (db < 50) return '安静（正常交谈）';
  if (db < 70) return '一般环境音';
  if (db < 85) return '偏吵（马路/地铁）';
  if (db < 100) return '嘈杂，长期听会伤听力';
  return '非常吵，建议离开';
}

/// 把一串分贝采样求平均（跳过明显无效的低值）。
double averageDb(List<double> samples) {
  final valid = samples.where((d) => d > -20).toList();
  if (valid.isEmpty) {
    throw const SensorToolError('还没采到有效数据');
  }
  return valid.reduce((a, b) => a + b) / valid.length;
}

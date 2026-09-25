// 主机指标的迷你折线（服务器页）。
//
// 自绘、零依赖：60 个点的百分比序列没必要引图表库。
// 与服务监控插件的迷你折线同形，但吃的是 0–100 的百分比：
//   * `null` 的采样**断开**（不连成直线——那是"没采到"，不是"0%"）；
//   * 纵向固定按 0–100 取比例，而不是按当前最大值：CPU 从 3% 涨到 8%
//     如果按最大值归一，看起来就像"飙到顶了"，会误报故障。
import 'package:flutter/material.dart';

class HostSparkline extends StatelessWidget {
  const HostSparkline({
    super.key,
    required this.values,
    this.width = 56,
    this.height = 16,
    this.warning = false,
  });

  /// 百分比序列（0–100）。
  final List<double> values;

  final double width;
  final double height;

  /// 当前值偏高时换告警色（由卡片按阈值决定）。
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (values.length < 2) {
      // 点太少画不出线，给一句说明而不是一个空框。
      return SizedBox(
        width: width,
        height: height,
        child: Center(
          child: Text(
            '暂无历史',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 8.5,
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: HostSparklinePainter(
          values: values,
          lineColor: warning ? theme.colorScheme.error : theme.colorScheme.primary,
          idleColor: theme.colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class HostSparklinePainter extends CustomPainter {
  HostSparklinePainter({
    required this.values,
    required this.lineColor,
    required this.idleColor,
  });

  final List<double> values;
  final Color lineColor;
  final Color idleColor;

  @override
  void paint(Canvas canvas, Size size) {
    final count = values.length;
    if (count < 2) return;

    final stepX = size.width / (count - 1);
    Offset pointFor(int i) {
      // 固定 0–100 比例（见文件头的说明），留 1px 边距避免贴边被裁。
      final ratio = (values[i] / 100).clamp(0.0, 1.0);
      return Offset(i * stepX, 1 + (size.height - 2) * (1 - ratio));
    }

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = lineColor;

    // 底边一条淡淡的基线，让"线贴着底"和"线在中间"一眼能分开。
    final baseline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = idleColor;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      baseline,
    );

    for (var i = 1; i < count; i++) {
      canvas.drawLine(pointFor(i - 1), pointFor(i), line);
    }
  }

  @override
  bool shouldRepaint(HostSparklinePainter old) =>
      old.values != values || old.lineColor != lineColor;
}

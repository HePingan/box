// 监控项的迷你折线（287 P3）。
//
// 自绘、零依赖：60 个点的序列没必要引图表库，也不该为了画一条线把包做大。
// 规矩：
//   * `null` 的采样**断开**（不能连成一条直线，那是"没采到"，不是"0ms"）；
//   * 不通的采样点用红色画在底部（一眼看出"哪一段是红的"）。
import 'package:flutter/material.dart';

class MonitorSparkline extends StatelessWidget {
  const MonitorSparkline({
    super.key,
    required this.pings,
    required this.ups,
    this.width = 64,
    this.height = 18,
  });

  /// 延迟序列（毫秒），null = 那次没采到。
  final List<int?> pings;

  /// 在线序列（1/0）；比 [pings] 短时以 [pings] 为准，反之亦然。
  final List<int> ups;

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = pings.length > ups.length ? pings.length : ups.length;
    if (count < 2) {
      // 点太少画不出线，给一句说明而不是一个空框。
      return SizedBox(
        width: width,
        height: height,
        child: Center(
          child: Text(
            '暂无历史',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
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
        painter: MonitorSparklinePainter(
          pings: pings,
          ups: ups,
          lineColor: theme.colorScheme.primary,
          downColor: theme.colorScheme.error,
          idleColor: theme.colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class MonitorSparklinePainter extends CustomPainter {
  MonitorSparklinePainter({
    required this.pings,
    required this.ups,
    required this.lineColor,
    required this.downColor,
    required this.idleColor,
  });

  final List<int?> pings;
  final List<int> ups;
  final Color lineColor;
  final Color downColor;
  final Color idleColor;

  @override
  void paint(Canvas canvas, Size size) {
    final count = pings.length > ups.length ? pings.length : ups.length;
    if (count < 2) return;

    int pingAt(int i) {
      if (i >= 0 && i < pings.length) {
        final v = pings[i];
        if (v != null) return v;
      }
      return -1;
    }

    bool upAt(int i) => i >= 0 && i < ups.length ? ups[i] == 1 : true;

    // 纵向比例：用**已采到**的最大值当上限（全都没采到就按 1 处理，避免除零）。
    var maxPing = 1;
    for (var i = 0; i < count; i++) {
      final v = pingAt(i);
      if (v > maxPing) maxPing = v;
    }

    final stepX = size.width / (count - 1);
    Offset pointFor(int i) {
      final v = pingAt(i);
      // 有采样：越高越靠上（留 2px 边距）；没采样或不通：贴着底边。
      if (v < 0) return Offset(i * stepX, size.height - 1);
      final ratio = (v / maxPing).clamp(0.0, 1.0);
      return Offset(i * stepX, 1 + (size.height - 2) * (1 - ratio));
    }

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    // 连续段：两端都有采样才连；中间断一格就断开（不连成直线骗人）。
    for (var i = 1; i < count; i++) {
      if (pingAt(i) < 0 || pingAt(i - 1) < 0) continue;
      line.color = upAt(i) && upAt(i - 1) ? lineColor : downColor;
      canvas.drawLine(pointFor(i - 1), pointFor(i), line);
    }

    // 不通的采样画一个红点，保证"掉线"在图上一定看得见。
    final dot = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < count; i++) {
      if (upAt(i)) continue;
      dot.color = downColor;
      canvas.drawCircle(pointFor(i), 1.6, dot);
    }
  }

  @override
  bool shouldRepaint(MonitorSparklinePainter old) =>
      old.pings != pings || old.ups != ups || old.lineColor != lineColor;
}

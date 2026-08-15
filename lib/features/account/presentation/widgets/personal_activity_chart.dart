import 'package:flutter/material.dart';

import '../../domain/personal_center_models.dart';

/// 30 天生图活跃趋势柱状图。
///
/// 不引入图表依赖，用 CustomPainter 直接绘制，数据来自 `/api/me/activity`。
class PersonalActivityChart extends StatelessWidget {
  const PersonalActivityChart({
    super.key,
    required this.days,
    this.height = 96,
  });

  final List<PersonalActivityDay> days;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('暂无活跃数据', style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }
    final maxRequests = days.fold<int>(
      0,
      (max, day) => day.requests > max ? day.requests : max,
    );
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _ActivityBarPainter(
              days: days,
              maxRequests: maxRequests,
              barColor: scheme.primary,
              failedColor: scheme.error,
              baselineColor: scheme.outlineVariant,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(days.first.date, style: Theme.of(context).textTheme.bodySmall),
            Text(
              maxRequests == 0 ? '近 30 天无生图记录' : '峰值 $maxRequests 次/日',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(days.last.date, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _ActivityBarPainter extends CustomPainter {
  const _ActivityBarPainter({
    required this.days,
    required this.maxRequests,
    required this.barColor,
    required this.failedColor,
    required this.baselineColor,
  });

  final List<PersonalActivityDay> days;
  final int maxRequests;
  final Color barColor;
  final Color failedColor;
  final Color baselineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = Paint()
      ..color = baselineColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      baseline,
    );
    if (maxRequests <= 0) return;

    final slot = size.width / days.length;
    final barWidth = (slot * 0.6).clamp(1.0, 12.0);
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      if (day.requests <= 0) continue;
      final ratio = day.requests / maxRequests;
      final barHeight = (size.height - 2) * ratio;
      final left = i * slot + (slot - barWidth) / 2;
      final top = size.height - barHeight;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, barHeight),
        const Radius.circular(2),
      );
      // 成功部分用主色，失败部分叠加错误色，直观体现失败占比。
      canvas.drawRect(rect.outerRect, Paint()..color = failedColor);
      final successRatio = day.requests == 0 ? 0.0 : day.success / day.requests;
      final successHeight = barHeight * successRatio;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            left,
            size.height - successHeight,
            barWidth,
            successHeight,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = barColor,
      );
    }
  }

  @override
  bool shouldRepaint(_ActivityBarPainter oldDelegate) =>
      oldDelegate.days != days ||
      oldDelegate.maxRequests != maxRequests ||
      oldDelegate.barColor != barColor;
}

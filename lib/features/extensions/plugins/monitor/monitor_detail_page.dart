// 单个监控项的详情（287 P3）。
//
// 回答三件首页回答不了的事：刚才是不是在抖（最近心跳列表）、什么时候开始不通的、
// 证书还剩多少天。**不引依赖、不连 Kuma**：数据全部来自那份静态快照。
import 'package:flutter/material.dart';

import 'monitor_models.dart';
import 'monitor_sparkline.dart';

class MonitorDetailPage extends StatelessWidget {
  const MonitorDetailPage({
    super.key,
    required this.entry,
    this.generatedAt,
  });

  final MonitorEntry entry;

  /// 快照采样时刻：用来把"最近心跳"标上时间（没有就只显示延迟）。
  final DateTime? generatedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = entry.up ? const Color(0xFF16A34A) : theme.colorScheme.error;
    final certLabel = entry.certificateLabel;

    return Scaffold(
      appBar: AppBar(title: Text(entry.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Text(
                entry.up ? '正常' : '异常',
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              if (entry.pingMs != null) ...[
                const SizedBox(width: 12),
                Text(
                  '当前延迟 ${monitorPingText(entry.pingMs)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // 不通的时候把"从什么时候开始"直接写在最上面：这是最想知道的一句话。
          if (entry.downSinceLabel != null)
            Text(
              entry.downSinceLabel!,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          const SizedBox(height: 16),
          _Section(
            title: '最近 ${entry.seriesLength} 次采样',
            child: entry.hasSeries
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MonitorSparkline(
                        pings: entry.pingSeries,
                        ups: entry.upSeries,
                        width: MediaQuery.of(context).size.width - 64,
                        height: 64,
                      ),
                      const SizedBox(height: 12),
                      ..._recentRows(theme),
                    ],
                  )
                : Text(
                    '这份快照里没有历史（服务端要攒够两次采样才有）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: '其它',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv(theme, '24 小时可用率', monitorUptimeText(entry.uptime24h)),
                if (certLabel != null)
                  _kv(
                    theme,
                    '证书',
                    certLabel,
                    valueColor: entry.certificateWarning ? theme.colorScheme.error : null,
                  ),
                _kv(
                  theme,
                  '采样时刻',
                  monitorAgeText(generatedAt) ?? '时间未知',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 最近几次心跳：时间倒序，一眼看出"这几分钟是不是都在抖"。
  List<Widget> _recentRows(ThemeData theme) {
    const shown = 12;
    final total = entry.seriesLength;
    final start = total > shown ? total - shown : 0;
    final rows = <Widget>[];
    for (var i = total - 1; i >= start; i--) {
      final ping = i < entry.pingSeries.length ? entry.pingSeries[i] : null;
      final up = i < entry.upSeries.length ? entry.upSeries[i] == 1 : true;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox(
                width: 62,
                child: Text(
                  _timeLabel(total - 1 - i),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              SizedBox(
                width: 74,
                child: Text(
                  up ? monitorPingText(ping) : '不通',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: up ? null : theme.colorScheme.error,
                    fontWeight: up ? null : FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  /// `i` 次采样之前 → 时刻文案（没有采样时刻就只写"第 N 次前"）。
  String _timeLabel(int samplesAgo) {
    final at = generatedAt;
    if (at == null) return '$samplesAgo 次前';
    final t = at.toLocal().subtract(
          Duration(seconds: samplesAgo * entry.seriesStepSec),
        );
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${two(t.hour)}:${two(t.minute)}';
  }

  Widget _kv(ThemeData theme, String key, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              key,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        child,
      ],
    );
  }
}

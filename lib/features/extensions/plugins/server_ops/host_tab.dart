// 服务器运维插件：「服务器」页签 —— 各主机的 CPU / 内存 / 磁盘 / 负载 / 网络，
// 以及扩展的盘 IO / Swap / 温度（**取不到的那几行整体不显示**，见文件末尾的参数）。
//
// 形状与「服务监控」页一致：
//   * 冷启动先用上次成功的快照渲染，同时后台刷新（不转圈等网络）；
//   * 刷新失败**保留旧内容**，把原因写进横幅（"显示的是上次的内容（N 分钟前）"）；
//   * 明确显示服务端的 `generatedAt`（采样时刻）——数据源是 2 分钟一份的静态
//     文件，**不能假装是实时的**；
//   * 离线机器只显示"离线"，不显示 0%（缺字段 ≠ 0）。

import 'package:flutter/material.dart';

import 'package:box/features/extensions/plugins/server_ops/host_models.dart';
import 'package:box/features/extensions/plugins/server_ops/host_service.dart';
import 'package:box/features/extensions/plugins/server_ops/host_sparkline.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_runtime.dart';

/// 指标高到这个值就换告警色（阈值是给"看一眼有没有事"用的，不是告警系统）。
const double kHostCpuWarnPercent = 85;
const double kHostMemWarnPercent = 90;
const double kHostDiskWarnPercent = 90;

class ServerOpsHostTab extends StatefulWidget {
  const ServerOpsHostTab({super.key});

  @override
  State<ServerOpsHostTab> createState() => _ServerOpsHostTabState();
}

class _ServerOpsHostTabState extends State<ServerOpsHostTab> {
  HostSnapshot? _snapshot;
  DateTime? _shownAt;
  String? _error;
  bool _loading = false;
  Map<String, HostHistory> _histories = const {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// 先展示缓存与历史，再刷新。
  Future<void> _bootstrap() async {
    final histories = await serverOpsHostService.loadHistories();
    final cached = await serverOpsHostService.cached();
    if (!mounted) return;
    setState(() {
      _histories = histories;
      if (cached != null) {
        _snapshot = cached.snapshot;
        _shownAt = cached.fetchedAt;
      }
    });
    await refresh();
  }

  /// 刷新一次（下拉刷新与右上角按钮都走它）。
  Future<void> refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final snapshot = await serverOpsHostService.fetch();
      final histories = await serverOpsHostService.recordSample(snapshot);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _shownAt = DateTime.now();
        _error = null;
        _loading = false;
        _histories = histories;
      });
    } on HostFetchException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 清除本地快照与历史再拉一次。
  Future<void> _clearCacheAndRefresh() async {
    await serverOpsHostService.clearCache();
    await serverOpsHostService.clearHistories();
    if (!mounted) return;
    setState(() {
      _snapshot = null;
      _shownAt = null;
      _error = null;
      _histories = const {};
    });
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = _snapshot;
    if (snapshot == null) {
      return _loading
          ? const Center(child: CircularProgressIndicator())
          : _ErrorView(message: _error, onRetry: refresh);
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          _StatusBanner(
            loading: _loading,
            error: _error,
            ageText: hostAgeText(_shownAt),
          ),
          const SizedBox(height: 10),
          _SampledAtRow(
            generatedAt: snapshot.generatedAt,
            loading: _loading,
            onRefresh: refresh,
            onClear: _clearCacheAndRefresh,
          ),
          const SizedBox(height: 10),
          _SummaryRow(snapshot: snapshot),
          const SizedBox(height: 12),
          for (final host in snapshot.hosts)
            _HostCard(
              host: host,
              history: _histories[host.id] ?? const HostHistory(),
              stepSec: kHostSampleStepSec,
            ),
          if (snapshot.hosts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  '这份快照里没有主机',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 采样时刻 + 刷新 / 清缓存入口。
///
/// 单独一行、显式写"采样时刻"：这张页面上的所有数字都属于那一刻，
/// 把它藏进小字里会让人以为看到的是"现在"。
class _SampledAtRow extends StatelessWidget {
  const _SampledAtRow({
    required this.generatedAt,
    required this.loading,
    required this.onRefresh,
    required this.onClear,
  });

  final DateTime? generatedAt;
  final bool loading;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final age = hostAgeText(generatedAt);
    final text = generatedAt == null
        ? '采样时刻未知'
        : '采样时刻 ${_formatStamp(generatedAt!)}'
            '${age == null ? '' : '（$age）'}';
    return Row(
      children: [
        Icon(Icons.schedule_rounded, size: 15, color: theme.colorScheme.outline),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
        if (loading)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          IconButton(
            tooltip: '刷新',
            visualDensity: VisualDensity.compact,
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 18),
          ),
        PopupMenuButton<String>(
          tooltip: '更多',
          onSelected: (value) async {
            if (value == 'clear') await onClear();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'clear',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline_rounded),
                title: Text('清除本地快照'),
                subtitle: Text('快照与历史折线一起清掉'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.snapshot});

  final HostSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offline = snapshot.offlineCount;
    final ok = offline == 0;
    final color = ok ? const Color(0xFF16A34A) : theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.error_rounded,
            color: color,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ok ? '全部在线' : '$offline 台离线',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          Text(
            '${snapshot.onlineCount} / ${snapshot.total} 台在线',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard({
    required this.host,
    required this.history,
    required this.stepSec,
  });

  final HostEntry host;
  final HostHistory history;

  /// 相邻历史点的间隔（秒）；文案里用它说明"这段线有多长"。
  final int stepSec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = host.online ? const Color(0xFF16A34A) : theme.colorScheme.outline;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  host.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                host.online ? '在线' : '离线',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            host.ip == null || host.ip!.isEmpty ? 'IP 未知' : host.ip!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 10),
          if (!host.online)
            Text(
              '这台机器当前离线，没有指标可显示（不是 0%）。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            )
          else ...[
            _MetricRow(
              label: 'CPU',
              value: host.cpuCount == null
                  ? hostPercentText(host.cpuPercent)
                  : '${hostPercentText(host.cpuPercent)} · ${host.cpuCount} 核',
              series: history.cpu,
              percent: host.cpuPercent,
              warnAt: kHostCpuWarnPercent,
            ),
            _MetricRow(
              label: '内存',
              value: hostUsageText(
                host.memUsedBytes,
                host.memTotalBytes,
                host.memPercent,
              ),
              series: history.mem,
              percent: host.memPercent,
              warnAt: kHostMemWarnPercent,
            ),
            _MetricRow(
              label: '磁盘',
              value: hostUsageText(
                host.diskUsedBytes,
                host.diskTotalBytes,
                host.diskPercent,
              ),
              series: history.disk,
              percent: host.diskPercent,
              warnAt: kHostDiskWarnPercent,
            ),
            const SizedBox(height: 6),
            _FactLine(
              icon: Icons.speed_rounded,
              text: '负载 ${hostLoadText(host.load1, host.load5, host.load15)}',
            ),
            _FactLine(
              icon: Icons.timelapse_rounded,
              text: '运行 ${hostUptimeText(host.uptimeSeconds)}',
            ),
            _FactLine(
              icon: Icons.swap_vert_rounded,
              text: '↓ ${hostRateText(host.netRxBytesPerSec)}'
                  '  /  ↑ ${hostRateText(host.netTxBytesPerSec)}',
            ),
            // 扩展指标：**取不到就整行不显示**（云主机没温度传感器、老快照没这两个
            // 字段都是常态）。显示 0 B/s 或 0℃ 会被读成"盘很闲 / 机器很凉"，
            // 缺字段 ≠ 0，宁可少一行。
            if (hostDiskIoText(host.diskReadBytesPerSec, host.diskWriteBytesPerSec)
                case final diskIo?)
              _FactLine(
                icon: Icons.storage_rounded,
                text: '盘 IO $diskIo',
              ),
            if (host.swapTotalBytes case final swapTotal?)
              if (swapTotal > 0)
                _FactLine(
                  icon: Icons.memory_rounded,
                  text: 'Swap '
                      '${hostUsageText(host.swapUsedBytes, swapTotal, host.swapPercent)}',
                ),
            if (host.temperatureC case final temperature?)
              _FactLine(
                icon: Icons.thermostat_rounded,
                text: '温度 ${hostTempText(temperature)}',
              ),
            if (history.hasAny)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '折线：最近 ${history.cpu.length} 个点，每点 '
                  '${stepSec ~/ 60} 分钟',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 一行指标：名称 / 值 / 迷你折线。
class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.series,
    required this.percent,
    required this.warnAt,
  });

  final String label;
  final String value;
  final List<double> series;
  final double? percent;
  final double warnAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warn = percent != null && percent! >= warnAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: warn ? FontWeight.w700 : FontWeight.w500,
                color: warn ? theme.colorScheme.error : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          HostSparkline(values: series, warning: warn),
        ],
      ),
    );
  }
}

class _FactLine extends StatelessWidget {
  const _FactLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部横幅：正在刷新 / 刷新失败但保留旧内容。
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.loading,
    required this.error,
    required this.ageText,
  });

  final bool loading;
  final String? error;
  final String? ageText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final age = ageText;
    if (error != null) {
      final suffix = age == null ? '' : ' · 显示的是上次的内容（$age）';
      return _Banner(
        color: theme.colorScheme.errorContainer,
        icon: Icons.warning_amber_rounded,
        text: '刷新失败：$error$suffix',
      );
    }
    if (loading && age != null) {
      return _Banner(
        color: theme.colorScheme.surfaceContainerHighest,
        icon: Icons.sync_rounded,
        text: '正在刷新…（当前显示 $age 的数据）',
      );
    }
    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String? message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 44,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text('拿不到主机快照', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              message ?? '未知原因',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 采样时刻的本地时间显示（不引入 intl：这个仓库存的是朴素格式）。
String _formatStamp(DateTime at) {
  final local = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

// 服务监控插件（box 内置插件）：把 Kuma 的探针状态放进 app。
//
// 形状与远端存储插件一致：
//   * 冷启动先用上次成功的快照渲染，同时后台刷新（不转圈等网络）；
//   * 刷新失败**保留旧内容**，把原因写进横幅，不整页报错；
//   * 服务通过 debugSetServiceMonitorRuntime 注入，widget 测试不碰真网络。
//
// 仓库没有 url_launcher（见 announcement_popup.dart 里的说明），所以面板入口
// 给「复制地址」而不是可点链接。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:box/features/extensions/plugins/monitor/monitor_detail_page.dart';
import 'package:box/features/extensions/plugins/monitor/monitor_models.dart';
import 'package:box/features/extensions/plugins/monitor/monitor_service.dart';
import 'package:box/features/extensions/plugins/monitor/monitor_sparkline.dart';

/// 页面用的服务实例（测试可替换）。
ServiceMonitorService _runtimeService = ServiceMonitorService();

/// 测试接缝：与 `debugSetRemoteStorageRuntime` 同形状；不传参恢复默认。
void debugSetServiceMonitorRuntime({ServiceMonitorService? service}) {
  _runtimeService = service ?? ServiceMonitorService();
}

/// 当前生效的服务（也供测试读，确认页面用的是注入的那个）。
ServiceMonitorService get debugServiceMonitorService => _runtimeService;

class ServiceMonitorPage extends StatefulWidget {
  const ServiceMonitorPage({super.key});

  @override
  State<ServiceMonitorPage> createState() => _ServiceMonitorPageState();
}

class _ServiceMonitorPageState extends State<ServiceMonitorPage> {
  MonitorSnapshot? _snapshot;
  DateTime? _shownAt;
  String? _error;
  bool _loading = false;
  bool _copyDone = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// 先展示缓存，再刷新。
  Future<void> _bootstrap() async {
    final cached = await _runtimeService.cached();
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        _snapshot = cached.snapshot;
        _shownAt = cached.fetchedAt;
      });
    }
    await refresh();
  }

  /// 刷新一次（下拉刷新与右上角按钮都走它）。
  Future<void> refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final snapshot = await _runtimeService.fetch();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _shownAt = DateTime.now();
        _error = null;
        _loading = false;
      });
    } on MonitorFetchException catch (e) {
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

  /// 清除本地快照再拉一次：快照坏了/想强制刷新时的入口
  /// （本地只缓存"上一次成功的结果"，没有别的副作用）。
  Future<void> _clearCacheAndRefresh() async {
    await _runtimeService.clearCache();
    if (!mounted) return;
    setState(() {
      _snapshot = null;
      _shownAt = null;
      _error = null;
    });
    await refresh();
  }

  Future<void> _copyPanelUrl() async {
    final url = _snapshot?.panelUrl;
    if (url == null || url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() => _copyDone = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('监控面板地址已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('服务监控'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) async {
              if (value == 'clear') await _clearCacheAndRefresh();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('清除本地快照'),
                  subtitle: Text('下次打开重新拉取'),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : refresh,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return _loading ? const _Busy() : _ErrorView(message: _error, onRetry: refresh);
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _StatusBanner(
            loading: _loading,
            error: _error,
            ageText: monitorAgeText(_shownAt),
            // 快照太旧（287 D4）：看**服务端的采样时刻**，不是本地拉取时刻 ——
            // 拉取成功但内容两天没变，那正是"采样链断了"的样子。
            stale: isMonitorSnapshotStale(snapshot.generatedAt),
            snapshotAgeText: monitorAgeText(snapshot.generatedAt),
          ),
          const SizedBox(height: 12),
          _SummaryCard(
            snapshot: snapshot,
            onCopyPanelUrl: _copyPanelUrl,
            copied: _copyDone,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '监控项（${snapshot.total}）',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (final entry in snapshot.monitors)
            _MonitorTile(entry: entry, generatedAt: snapshot.generatedAt),
          if (snapshot.monitors.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  '这份快照里没有监控项',
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

class _Busy extends StatelessWidget {
  const _Busy();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
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
            const Text('拿不到监控快照', style: TextStyle(fontWeight: FontWeight.w700)),
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

/// 顶部横幅：正在刷新 / 刷新失败但保留旧内容 / 全部在线。
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.loading,
    required this.error,
    required this.ageText,
    this.stale = false,
    this.snapshotAgeText,
  });

  final bool loading;
  final String? error;
  final String? ageText;

  /// 快照比阈值还旧（287 D4）。刷新中/失败另有横幅，那两种优先。
  final bool stale;

  /// 服务端采样时刻的"多久之前"（陈旧横幅里用这个，别用本地拉取时刻）。
  final String? snapshotAgeText;

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
    if (loading) {
      final suffix = age == null ? '' : '（当前显示 $age 的数据）';
      return _Banner(
        color: theme.colorScheme.surfaceContainerHighest,
        icon: Icons.sync_rounded,
        text: '正在刷新…$suffix',
      );
    }
    if (stale) {
      final sampled = snapshotAgeText;
      final suffix = sampled == null ? '' : '：内容是 $sampled 采样的';
      return _Banner(
        color: const Color(0xFFFFF3CD),
        icon: Icons.schedule_rounded,
        text: '快照已经很久没更新了$suffix。采样可能断了（服务端每 2 分钟一次）。',
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
            child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.snapshot,
    required this.onCopyPanelUrl,
    required this.copied,
  });

  final MonitorSnapshot snapshot;
  final Future<void> Function() onCopyPanelUrl;
  final bool copied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final down = snapshot.downCount;
    final ok = down == 0;
    final color = ok ? const Color(0xFF16A34A) : theme.colorScheme.error;
    final age = monitorAgeText(snapshot.generatedAt);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.error_rounded,
                color: color,
                size: 26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ok ? '全部在线' : '$down 项异常',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${snapshot.upCount} / ${snapshot.total} 项在线'
                      '${age == null ? '' : ' · 采样于 $age'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  snapshot.panelUrl ?? 'https://ham.hpa888.top/',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: onCopyPanelUrl,
                icon: Icon(copied ? Icons.check_rounded : Icons.copy_rounded, size: 16),
                label: Text(copied ? '已复制' : '复制面板地址'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 行内第二行：延迟 · 24h 可用率 · 证书剩余。
/// 证书快到期/已失效时那一段换色（其余保持次要色，避免整行都在喊）。
class _MonitorSubtitle extends StatelessWidget {
  const _MonitorSubtitle({required this.entry, required this.theme});

  final MonitorEntry entry;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final base = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.outline,
    );
    final parts = <String>[
      '延迟 ${monitorPingText(entry.pingMs)}',
      '24h 可用率 ${monitorUptimeText(entry.uptime24h)}',
    ];
    final cert = entry.certificateLabel;
    return Row(
      children: [
        Flexible(
          child: Text(
            parts.join(' · '),
            style: base,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (cert != null) ...[
          Text(' · ', style: base),
          Text(
            cert,
            style: base?.copyWith(
              color: entry.certificateWarning
                  ? const Color(0xFFB45309)
                  : theme.colorScheme.outline,
              fontWeight: entry.certificateWarning ? FontWeight.w700 : null,
            ),
          ),
        ],
      ],
    );
  }
}

class _MonitorTile extends StatelessWidget {
  const _MonitorTile({required this.entry, this.generatedAt});

  final MonitorEntry entry;

  /// 传给详情页，用来给"最近心跳"标上时刻。
  final DateTime? generatedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = entry.up ? const Color(0xFF16A34A) : theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // 点进详情（287 P3）：列表只能看"现在"，趋势与"什么时候开始不通"在详情里。
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MonitorDetailPage(
              entry: entry,
              generatedAt: generatedAt,
            ),
          ),
        ),
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  _MonitorSubtitle(entry: entry, theme: theme),
                ],
              ),
            ),
            // 迷你折线（287 P3）：一眼看出"这段是不是红的"。
            // 点太少时组件自己会说"暂无历史"——比有条件地不渲染更好：
            // 用户看到的是"没有历史"，而不是"这里本该有东西但没了"。
            const SizedBox(width: 8),
            MonitorSparkline(pings: entry.pingSeries, ups: entry.upSeries),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  entry.up ? '正常' : '异常',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                if (entry.downSinceLabel != null)
                  Text(
                    entry.downSinceLabel!,
                    style: theme.textTheme.labelSmall?.copyWith(color: color),
                  ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

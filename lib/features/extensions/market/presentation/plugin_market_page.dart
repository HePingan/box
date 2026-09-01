import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:box/core/load_generation.dart';
import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_bottom_sheet.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';
import 'package:box/features/extensions/market/data/plugin_market_api.dart';
import 'package:box/features/extensions/market/data/plugin_market_manifest_repository.dart';
import 'package:box/features/extensions/market/domain/plugin_market_manifest.dart';
import 'package:box/plugin_market/models/plugin_market_security.dart';

import 'widgets/plugin_market_widgets.dart';

typedef MarketInstallHandler = Future<void> Function(
  MarketPluginTemplate template, {
  void Function(int receivedBytes, int totalBytes)? onProgress,
});

typedef MarketUninstallHandler = Future<void> Function(String pluginId);

class PluginMarketPage extends StatefulWidget {
  PluginMarketPage({
    super.key,
    required this.initialInstalledIds,
    required this.onInstall,
    required this.onUninstall,
    this.templates = const [],
    this.remoteConfigUrl,
    this.initialChannel = PluginMarketChannel.stable,
    this.securityConfig = const PluginMarketSecurityConfig(),
    this.initialInstalledVersions = const {},
    PluginMarketManifestRepository? manifestRepository,
  }) : manifestRepository =
           manifestRepository ?? PluginMarketManifestRepository.instance;

  final Set<String> initialInstalledIds;
  final MarketInstallHandler onInstall;
  final MarketUninstallHandler onUninstall;
  final List<MarketPluginTemplate> templates;
  final PluginMarketManifestRepository manifestRepository;

  /// 远程清单 URL
  final String? remoteConfigUrl;

  /// 初始频道
  final PluginMarketChannel initialChannel;

  /// 验签配置
  final PluginMarketSecurityConfig securityConfig;

  /// 本地已装版本（id → version）
  final Map<String, String> initialInstalledVersions;

  @override
  State<PluginMarketPage> createState() => _PluginMarketPageState();
}

class _PluginMarketPageState extends State<PluginMarketPage> {
  List<MarketPluginTemplate> _allTemplates = [];
  late Set<String> _installedIds;

  final Set<String> _loadingIds = {};
  final Map<String, double> _installProgress = {};
  late final TextEditingController _searchController;
  bool _bulkRunning = false;
  bool _marketLoading = true;

  String _keyword = '';
  String _areaFilter = 'all';
  String _tagFilter = 'all';
  // 排序：recommended(默认) | downloads | updated | title
  String _sortBy = 'recommended';

  late PluginMarketChannel _currentChannel;

  /// 清单加载的请求身份守卫（intent = 频道）。
  final LoadGeneration _marketGeneration = LoadGeneration();

  String _marketSource = 'builtin';
  int _marketVersion = 1;
  DateTime? _marketFetchedAt;

  bool _signatureVerified = false;
  PluginMarketSignMode _signatureMode = PluginMarketSignMode.none;
  String _signatureMessage = '';

  @override
  void initState() {
    super.initState();
    _installedIds = {...widget.initialInstalledIds};
    _searchController = TextEditingController();
    _currentChannel = widget.initialChannel;
    _loadMarket(forceRefresh: false);
  }

  @override
  void dispose() {
    // 作废在途清单请求，回来后直接丢弃。
    _marketGeneration.invalidate();
    _searchController.dispose();
    super.dispose();
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _searchController.clear();
      _keyword = '';
      _areaFilter = 'all';
    });
  }

  Future<void> _loadMarket({required bool forceRefresh}) async {
    // intent 用频道：既防「后发先至」（旧代号），也防「同代号但频道已变」。
    // 没有这道闸，慢的 stable 响应回来会把 _currentChannel 改回 stable，
    // 用户明明已经切到 Beta，列表和频道标记却被旧清单覆盖。
    final token = _marketGeneration.begin(_currentChannel);
    setState(() => _marketLoading = true);

    try {
      final fallback = widget.templates.isEmpty
          ? MarketPluginTemplate.defaults
          : widget.templates;

      final manifest = await widget.manifestRepository.loadManifest(
        fallbackTemplates: fallback,
        channel: _currentChannel,
        security: widget.securityConfig,
        remoteConfigUrl: widget.remoteConfigUrl,
        forceRefresh: forceRefresh,
      );

      if (!mounted || !_marketGeneration.isCurrent(token)) return;

      setState(() {
        _allTemplates = manifest.templates;
        _marketSource = manifest.source;
        _marketVersion = manifest.version;
        _marketFetchedAt = manifest.fetchedAt;
        _signatureVerified = manifest.signatureVerified;
        _signatureMode = manifest.signatureMode;
        _signatureMessage = manifest.signatureMessage;
        _currentChannel = manifest.channel;
        _marketLoading = false;
      });

      final hasRemote = (widget.remoteConfigUrl ?? '').trim().isNotEmpty;
      if (forceRefresh && hasRemote && manifest.source != 'remote') {
        _showSnack('远程拉取失败，已回退到${_sourceLabel(manifest.source)}');
      }

      if (manifest.source == 'remote' &&
          widget.securityConfig.mode != PluginMarketSignMode.none &&
          !manifest.signatureVerified) {
        _showSnack('远程清单验签未通过：${manifest.signatureMessage}');
      }
    } catch (e) {
      // 过期请求的失败不得写状态：否则旧请求的报错会盖掉新请求的加载态，
      // 还会弹一条与当前频道无关的错误提示。
      if (!mounted || !_marketGeneration.isCurrent(token)) return;
      setState(() => _marketLoading = false);
      _showSnack('加载插件市场失败：$e');
    }
  }

  /// 仅测试用：驱动频道切换（等价于点击频道 Tab）。
  @visibleForTesting
  Future<void> switchChannelForTesting(PluginMarketChannel channel) =>
      _switchChannel(channel);

  /// 仅测试用：读取当前生效频道。
  @visibleForTesting
  PluginMarketChannel get currentChannelForTesting => _currentChannel;

  Future<void> _switchChannel(PluginMarketChannel channel) async {
    if (_currentChannel == channel) return;

    setState(() {
      _currentChannel = channel;
      _searchController.clear();
      _keyword = '';
      _areaFilter = 'all';
    });

    await _loadMarket(forceRefresh: false);
  }

  /// 当前频道下可用标签及数量（用于渲染标签筛选栏）。
  List<MapEntry<String, int>> get _availableTags {
    final counts = <String, int>{};
    for (final item in _allTemplates) {
      for (final t in item.tags) {
        final k = t.trim();
        if (k.isEmpty) continue;
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  List<MarketPluginTemplate> get _visibleTemplates {
    final keyword = _keyword.trim().toLowerCase();
    final tag = _tagFilter.toLowerCase();

    final list = _allTemplates.where((item) {
      final areaOk = _areaFilter == 'all' || item.areaCode == _areaFilter;
      if (!areaOk) return false;

      final tagOk = _tagFilter == 'all' ||
          item.tags.any((t) => t.toLowerCase() == tag);
      if (!tagOk) return false;

      if (keyword.isEmpty) return true;

      final joined =
          '${item.title} ${item.subtitle} ${item.payload} ${item.author} ${item.tags.join(' ')}'
              .toLowerCase();
      return joined.contains(keyword);
    }).toList();

    int cmpRecommended(MarketPluginTemplate a, MarketPluginTemplate b) {
      final c = a.sort.compareTo(b.sort);
      if (c != 0) return c;
      return a.title.compareTo(b.title);
    }

    switch (_sortBy) {
      case 'downloads':
        list.sort((a, b) => b.downloadCount.compareTo(a.downloadCount));
        break;
      case 'updated':
        list.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
        break;
      case 'title':
        list.sort((a, b) => a.title.compareTo(b.title));
        break;
      default:
        list.sort(cmpRecommended);
    }

    return list;
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'remote':
        return '远程';
      case 'cache':
        return '缓存';
      case 'builtin':
      default:
        return '内置';
    }
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '--';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _verifyLabel() {
    if (_signatureMode == PluginMarketSignMode.none) return '关闭';
    return _signatureVerified ? '通过' : '未通过';
  }

  String _areaLabel(String code) {
    switch (code) {
      case 'recommend':
        return '推荐';
      case 'music':
        return '音乐';
      case 'video':
        return '影视';
      case 'comic':
        return '漫画';
      case 'novel':
        return '小说';
      default:
        return code;
    }
  }

  String _actionLabel(String code) {
    switch (code) {
      case 'toast':
        return '提示动作';
      case 'openDailyNews':
        return '打开日报';
      case 'openNovelList':
        return '打开小说';
      case 'openVideoList':
        return '打开影视';
      case 'openImageGenerator':
        return '打开生图';
      default:
        return code;
    }
  }

  Future<PluginCompatibilityResult> _checkCompatibility(
    MarketPluginTemplate item,
  ) async {
    final packageInfo = await PackageInfo.fromPlatform();
    return PluginCompatibilityChecker.check(
      item,
      currentAppVersion: packageInfo.version,
    );
  }

  Future<bool> _confirmInstallCompatibility(MarketPluginTemplate item) async {
    final result = await _checkCompatibility(item);
    if (!mounted) return false;

    if (!result.canInstall) {
      await _showCompatibilityIssues(
        title: '无法安装插件',
        item: item,
        issues: result.blockingIssues,
        blocking: true,
      );
      return false;
    }

    if (result.warningIssues.isNotEmpty) {
      return _showCompatibilityIssues(
        title: '安装前确认',
        item: item,
        issues: result.warningIssues,
        blocking: false,
      );
    }

    return true;
  }

  Future<bool> _showCompatibilityIssues({
    required String title,
    required MarketPluginTemplate item,
    required List<PluginCompatibilityIssue> issues,
    required bool blocking,
  }) async {
    final result = await showAppModalBottomSheet<bool>(
      context: context,
      builder: (dialogContext) => AppBottomSheetFrame(
        title: title,
        subtitle: item.title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: blocking
                    ? AppTokens.rose.withValues(alpha: 0.08)
                    : const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                border: Border.all(
                  color: blocking
                      ? AppTokens.rose.withValues(alpha: 0.18)
                      : const Color(0xFFFED7AA),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final issue in issues) ...[
                    Text(
                      '• ${issue.message}',
                      style: TextStyle(
                        color: blocking
                            ? AppTokens.rose
                            : const Color(0xFF92400E),
                        fontSize: 13,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(blocking ? '知道了' : '取消'),
                  ),
                ),
                if (!blocking) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('继续安装'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _install(MarketPluginTemplate item) async {
    if (_loadingIds.contains(item.id) || _bulkRunning) return;

    setState(() => _loadingIds.add(item.id));
    try {
      final canInstall = await _confirmInstallCompatibility(item);
      if (!canInstall) return;

      // 下载阶段：显示进度条
      setState(() => _installProgress[item.id] = 0);
      await widget.onInstall(item, onProgress: (received, total) {
        if (!mounted) return;
        final p = total > 0 ? received / total : 0.5;
        setState(() => _installProgress[item.id] = p.clamp(0.05, 0.95));
      });
      if (!mounted) return;
      setState(() {
        _installProgress[item.id] = 1.0;
        _installedIds.add(item.id);
      });
      _showSnack('安装成功：${item.title}');
    } catch (e) {
      if (!mounted) return;
      _showSnack(_err(e));
    } finally {
      if (mounted) {
        setState(() {
          _loadingIds.remove(item.id);
          _installProgress.remove(item.id);
        });
      }
    }
  }

  Future<void> _uninstall(MarketPluginTemplate item) async {
    if (_loadingIds.contains(item.id) || _bulkRunning) return;

    setState(() => _loadingIds.add(item.id));
    try {
      await widget.onUninstall(item.id);
      if (!mounted) return;
      setState(() => _installedIds.remove(item.id));
      _showSnack('已卸载：${item.title}');
    } catch (e) {
      if (!mounted) return;
      _showSnack(_err(e));
    } finally {
      if (mounted) setState(() => _loadingIds.remove(item.id));
    }
  }

  Future<void> _installVisible() async {
    if (_bulkRunning) return;

    final target = _visibleTemplates
        .where((e) => !_installedIds.contains(e.id))
        .toList();

    if (target.isEmpty) {
      _showSnack('当前筛选下没有可安装插件');
      return;
    }

    final confirmed = await _confirmBulkAction(
      title: '安装当前筛选插件',
      message: '将安装当前筛选结果中的 ${target.length} 个未安装插件，不会删除筛选条件。是否继续？',
      confirmText: '开始安装',
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    setState(() => _bulkRunning = true);

    var success = 0;
    var skipped = 0;
    final packageInfo = await PackageInfo.fromPlatform();
    for (final item in target) {
      final compatibility = PluginCompatibilityChecker.check(
        item,
        currentAppVersion: packageInfo.version,
      );
      if (!compatibility.canInstall || compatibility.warningIssues.isNotEmpty) {
        skipped++;
        continue;
      }

      try {
        await widget.onInstall(item);
        _installedIds.add(item.id);
        success++;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _bulkRunning = false);
    final skippedText = skipped > 0 ? '，已跳过 $skipped 个不兼容/需确认插件' : '';
    _showSnack('批量安装完成：$success / ${target.length}$skippedText');
  }

  Future<void> _removeVisible() async {
    if (_bulkRunning) return;

    final target = _visibleTemplates
        .where((e) => _installedIds.contains(e.id))
        .toList();

    if (target.isEmpty) {
      _showSnack('当前筛选下没有已安装插件');
      return;
    }

    final confirmed = await _confirmBulkAction(
      title: '卸载当前筛选插件',
      message: '将卸载当前筛选结果中的 ${target.length} 个已安装插件，不会删除筛选条件。是否继续？',
      confirmText: '确认卸载',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _bulkRunning = true);

    var success = 0;
    for (final item in target) {
      try {
        await widget.onUninstall(item.id);
        _installedIds.remove(item.id);
        success++;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _bulkRunning = false);
    _showSnack('批量卸载完成：$success / ${target.length}');
  }

  Future<bool> _confirmBulkAction({
    required String title,
    required String message,
    required String confirmText,
    required bool destructive,
  }) async {
    final result = await showAppModalBottomSheet<bool>(
      context: context,
      builder: (dialogContext) => AppBottomSheetFrame(
        title: title,
        subtitle: destructive ? '批量卸载会立即从当前设备移除插件' : '请确认本次批量操作',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: destructive
                    ? AppTokens.rose.withValues(alpha: 0.08)
                    : AppTokens.surfaceTint,
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                border: Border.all(
                  color: destructive
                      ? AppTokens.rose.withValues(alpha: 0.18)
                      : AppTokens.divider,
                ),
              ),
              child: Text(
                message,
                style: TextStyle(
                  color: destructive ? AppTokens.rose : AppTokens.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: destructive
                        ? FilledButton.styleFrom(
                            backgroundColor: AppTokens.rose,
                          )
                        : null,
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(confirmText),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  Widget _buildAreaChip(String code, String label) {
    final selected = _areaFilter == code;
    return GestureDetector(
      onTap: () => setState(() => _areaFilter = code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? AppTokens.violetGradient : null,
          color: selected ? null : Colors.white,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          border: Border.all(
            color: selected ? Colors.transparent : AppTokens.divider,
          ),
          boxShadow: selected
              ? AppTokens.shadowSm(color: AppTokens.violet)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTokens.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildChannelSwitch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          MarketPill(
            label: 'Stable',
            selected: _currentChannel == PluginMarketChannel.stable,
            onTap: () => _switchChannel(PluginMarketChannel.stable),
          ),
          MarketPill(
            label: 'Beta',
            selected: _currentChannel == PluginMarketChannel.beta,
            onTap: () => _switchChannel(PluginMarketChannel.beta),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaCard() {
    final remote = (widget.remoteConfigUrl ?? '').trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EAF2)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          MarketTagChip(text: '来源：${_sourceLabel(_marketSource)}'),
          MarketTagChip(text: '频道：${_currentChannel.label}'),
          MarketTagChip(text: '版本：v$_marketVersion'),
          MarketTagChip(text: '验签：${_verifyLabel()}'),
          MarketTagChip(
            text: '模式：${pluginMarketSignModeWireName(_signatureMode)}',
          ),
          MarketTagChip(text: '插件：${_allTemplates.length}'),
          MarketTagChip(text: '更新时间：${_fmtTime(_marketFetchedAt)}'),
          MarketTagChip(text: remote.isEmpty ? '远程：未配置' : '远程：已配置'),
        ],
      ),
    );
  }

  Widget _buildSignatureWarning() {
    final shouldWarn =
        _marketSource == 'remote' &&
        widget.securityConfig.mode != PluginMarketSignMode.none &&
        !_signatureVerified;

    if (!shouldWarn) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: Color(0xFFB45309),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '远程清单验签未通过：$_signatureMessage'
              '\n策略：${widget.securityConfig.allowUnsigned ? '允许放行' : '严格拒绝'}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(MarketPluginTemplate item) {
    final installed = _installedIds.contains(item.id);
    final loading = _loadingIds.contains(item.id) || _bulkRunning;

    // 内容页优化：题干优先，操作下沉；标签收敛，避免窄屏 trailing 挤裁
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: installed
              ? AppTokens.emerald.withValues(alpha: 0.26)
              : AppTokens.divider,
        ),
        boxShadow: AppTokens.shadowSm(color: item.color),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.icon, color: item.color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: AppTokens.textPrimary,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTokens.textSecondary,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                MarketStatusBadge(installed: installed),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                MarketTagChip(text: _areaLabel(item.areaCode)),
                MarketTagChip(text: _actionLabel(item.actionCode)),
                if (item.version.trim().isNotEmpty)
                  MarketTagChip(text: 'v${item.version}'),
                if (item.deprecated) const MarketTagChip(text: '已废弃'),
                for (final tag in item.tags.take(2)) MarketTagChip(text: tag),
                // 安装前的权限知情权：卡片直接标出插件申请的权限，
                // 用户投稿 → 管理员审核 → 他人安装 的链路里，普通用户
                // 装之前必须能看到它要什么（网络、打开页面等）。
                if (item.permissions.isNotEmpty)
                  MarketTagChip(text: '权限：${item.permissions.join('、')}'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (item.author.trim().isNotEmpty)
                  Expanded(
                    child: Text(
                      '作者：${item.author}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTokens.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                SizedBox(
                  height: 34,
                  child: loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : installed
                      ? OutlinedButton(
                          onPressed: () => _uninstall(item),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            foregroundColor: AppTokens.rose,
                            side: BorderSide(
                              color: AppTokens.rose.withValues(alpha: 0.38),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('卸载'),
                        )
                      : FilledButton(
                          onPressed: () => _install(item),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('安装'),
                        ),
                ),
              ],
            ),
            if (loading &&
                _installProgress[item.id] != null &&
                _installProgress[item.id]! < 1) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: _installProgress[item.id],
                  backgroundColor: AppTokens.divider,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppTokens.primaryBlue,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMarketHero(int visibleCount) {
    final installedCount = _installedIds.length;
    final totalCount = _allTemplates.length;
    // 内容页：压扁 Hero，列表更早进入视口
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTokens.divider),
        boxShadow: AppTokens.shadowSm(color: AppTokens.primaryBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '插件市场',
                      style: TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$_currentChannel · 已装 $installedCount / 共 $totalCount · 筛选 $visibleCount',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: '刷新远程配置',
                onPressed: _marketLoading
                    ? null
                    : () => _loadMarket(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _bulkRunning ? null : _installVisible,
                  icon: const Icon(Icons.download_done_rounded, size: 16),
                  label: const Text('安装筛选', style: TextStyle(fontSize: 13)),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _bulkRunning ? null : _removeVisible,
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('卸载筛选', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTokens.rose,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: BorderSide(
                      color: AppTokens.rose.withValues(alpha: 0.38),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // A3: 排序栏
  Widget _buildSortBar() {
    const opts = <(String, String)>[
      ('recommended', '推荐'),
      ('downloads', '下载量'),
      ('updated', '最近更新'),
      ('title', '名称'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.sort_rounded, size: 16, color: AppTokens.textSecondary),
          const SizedBox(width: 6),
          const Text(
            '排序',
            style: TextStyle(fontSize: 12.5, color: AppTokens.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (code, label) in opts) ...[
                    ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      selected: _sortBy == code,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _sortBy = code),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // A3: 标签筛选栏
  Widget _buildTagBar() {
    final tags = _availableTags;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterChip(
              label: const Text('全部标签', style: TextStyle(fontSize: 12)),
              selected: _tagFilter == 'all',
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _tagFilter = 'all'),
            ),
            const SizedBox(width: 6),
            for (final e in tags) ...[
              FilterChip(
                label: Text(
                  '${e.key} ${e.value}',
                  style: const TextStyle(fontSize: 12),
                ),
                selected: _tagFilter.toLowerCase() == e.key.toLowerCase(),
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(
                  () => _tagFilter =
                      _tagFilter.toLowerCase() == e.key.toLowerCase()
                          ? 'all'
                          : e.key,
                ),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _err(Object e) {
    if (e is PluginMarketApiException) return e.friendlyMessage;
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleTemplates;

    return AppPageScaffold(
      child: Column(
        children: [
          if (_marketLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadMarket(forceRefresh: true),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(child: _buildMarketHero(visible.length)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _keyword = v),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          hintText: '搜索插件名称/描述',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _keyword.trim().isEmpty
                              ? null
                              : IconButton(
                                  onPressed: _resetFilters,
                                  icon: const Icon(Icons.clear),
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Color(0xFFE7ECF5),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Color(0xFFE7ECF5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: _buildChannelSwitch()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildAreaChip('all', '全部'),
                          _buildAreaChip('recommend', '推荐'),
                          _buildAreaChip('music', '音乐'),
                          _buildAreaChip('video', '影视'),
                          _buildAreaChip('comic', '漫画'),
                          _buildAreaChip('novel', '小说'),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: _buildSortBar()),
                  if (_availableTags.isNotEmpty)
                    SliverToBoxAdapter(child: _buildTagBar()),
                  SliverToBoxAdapter(child: _buildMetaCard()),
                  SliverToBoxAdapter(child: _buildSignatureWarning()),
                  if (visible.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: MarketEmptyState(
                          loading: _marketLoading,
                          onReset: _resetFilters,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 104),
                      sliver: SliverList.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, index) => _buildCard(visible[index]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'design_system/app_tokens.dart';
import 'features/extensions/market/data/plugin_market_manifest_repository.dart';
import 'features/extensions/market/domain/plugin_market_manifest.dart';
import 'plugin_market/models/plugin_market_security.dart';

export 'features/extensions/market/domain/plugin_market_manifest.dart';

typedef MarketInstallHandler =
    Future<void> Function(MarketPluginTemplate template);

typedef MarketUninstallHandler = Future<void> Function(String pluginId);

class PluginMarketPage extends StatefulWidget {
  const PluginMarketPage({
    super.key,
    required this.initialInstalledIds,
    required this.onInstall,
    required this.onUninstall,
    this.templates = const [],
    this.remoteConfigUrl,
    this.initialChannel = PluginMarketChannel.stable,
    this.securityConfig = const PluginMarketSecurityConfig(),
  });

  final Set<String> initialInstalledIds;
  final MarketInstallHandler onInstall;
  final MarketUninstallHandler onUninstall;
  final List<MarketPluginTemplate> templates;

  /// 远程清单 URL
  final String? remoteConfigUrl;

  /// 初始频道
  final PluginMarketChannel initialChannel;

  /// 验签配置
  final PluginMarketSecurityConfig securityConfig;

  @override
  State<PluginMarketPage> createState() => _PluginMarketPageState();
}

class _PluginMarketPageState extends State<PluginMarketPage> {
  List<MarketPluginTemplate> _allTemplates = [];
  late Set<String> _installedIds;

  final Set<String> _loadingIds = {};
  late final TextEditingController _searchController;
  bool _bulkRunning = false;
  bool _marketLoading = true;

  String _keyword = '';
  String _areaFilter = 'all';

  late PluginMarketChannel _currentChannel;

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
    setState(() => _marketLoading = true);

    try {
      final fallback = widget.templates.isEmpty
          ? MarketPluginTemplate.defaults
          : widget.templates;

      final manifest = await PluginMarketManifestRepository.instance
          .loadManifest(
            fallbackTemplates: fallback,
            channel: _currentChannel,
            security: widget.securityConfig,
            remoteConfigUrl: widget.remoteConfigUrl,
            forceRefresh: forceRefresh,
          );

      if (!mounted) return;

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
      if (!mounted) return;
      setState(() => _marketLoading = false);
      _showSnack('加载插件市场失败：$e');
    }
  }

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

  List<MarketPluginTemplate> get _visibleTemplates {
    final keyword = _keyword.trim().toLowerCase();

    final list = _allTemplates.where((item) {
      final areaOk = _areaFilter == 'all' || item.areaCode == _areaFilter;
      if (!areaOk) return false;

      if (keyword.isEmpty) return true;

      final joined = '${item.title} ${item.subtitle} ${item.payload}'
          .toLowerCase();
      return joined.contains(keyword);
    }).toList();

    list.sort((a, b) {
      final c = a.sort.compareTo(b.sort);
      if (c != 0) return c;
      return a.title.compareTo(b.title);
    });

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
      default:
        return code;
    }
  }

  Future<void> _install(MarketPluginTemplate item) async {
    if (_loadingIds.contains(item.id) || _bulkRunning) return;

    setState(() => _loadingIds.add(item.id));
    try {
      await widget.onInstall(item);
      if (!mounted) return;
      setState(() => _installedIds.add(item.id));
      _showSnack('安装成功：${item.title}');
    } catch (e) {
      _showSnack('安装失败：$e');
    } finally {
      if (mounted) setState(() => _loadingIds.remove(item.id));
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
      _showSnack('卸载失败：$e');
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
    for (final item in target) {
      try {
        await widget.onInstall(item);
        _installedIds.add(item.id);
        success++;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _bulkRunning = false);
    _showSnack('批量安装完成：$success / ${target.length}');
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
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: AppTokens.rose)
                : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmText),
          ),
        ],
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
          borderRadius: BorderRadius.circular(999),
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
          _MarketPill(
            label: 'Stable',
            selected: _currentChannel == PluginMarketChannel.stable,
            onTap: () => _switchChannel(PluginMarketChannel.stable),
          ),
          _MarketPill(
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
          _TagChip(text: '来源：${_sourceLabel(_marketSource)}'),
          _TagChip(text: '频道：${_currentChannel.label}'),
          _TagChip(text: '版本：v$_marketVersion'),
          _TagChip(text: '验签：${_verifyLabel()}'),
          _TagChip(text: '模式：${pluginMarketSignModeWireName(_signatureMode)}'),
          _TagChip(text: '插件：${_allTemplates.length}'),
          _TagChip(text: '更新时间：${_fmtTime(_marketFetchedAt)}'),
          _TagChip(text: remote.isEmpty ? '远程：未配置' : '远程：已配置'),
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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: installed
              ? AppTokens.emerald.withValues(alpha: 0.26)
              : AppTokens.divider,
        ),
        boxShadow: AppTokens.shadowSm(color: item.color),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(item.icon, color: item.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppTokens.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _StatusBadge(installed: installed),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTokens.textSecondary,
                      height: 1.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _TagChip(text: _areaLabel(item.areaCode)),
                      _TagChip(text: _actionLabel(item.actionCode)),
                      _TagChip(text: _currentChannel.label),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 92,
              child: loading
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : installed
                  ? OutlinedButton(
                      onPressed: () => _uninstall(item),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        foregroundColor: AppTokens.rose,
                        side: BorderSide(
                          color: AppTokens.rose.withValues(alpha: 0.38),
                        ),
                      ),
                      child: const Text('卸载'),
                    )
                  : FilledButton(
                      onPressed: () => _install(item),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('安装'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketHero(int visibleCount) {
    final installedCount = _installedIds.length;
    final totalCount = _allTemplates.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
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
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '插件市场',
                      style: TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '搜索、验签、安装扩展 · 当前 ${_currentChannel.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
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
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MarketMetric(
                  value: '$totalCount',
                  label: '模板',
                  glass: false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MarketMetric(
                  value: '$visibleCount',
                  label: '筛选',
                  glass: false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MarketMetric(
                  value: '$installedCount',
                  label: '已装',
                  glass: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _bulkRunning ? null : _installVisible,
                  icon: const Icon(Icons.download_done_rounded, size: 18),
                  label: const Text('安装当前筛选'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _bulkRunning ? null : _removeVisible,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('卸载当前筛选'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTokens.rose,
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

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleTemplates;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
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
                    SliverToBoxAdapter(child: _buildMetaCard()),
                    SliverToBoxAdapter(child: _buildSignatureWarning()),
                    if (visible.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: _MarketEmptyState(
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
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) => _buildCard(visible[index]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketPill extends StatelessWidget {
  const _MarketPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? AppTokens.blueGradient : null,
          color: selected ? null : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? Colors.transparent : AppTokens.divider,
          ),
          boxShadow: selected
              ? AppTokens.shadowSm(color: AppTokens.primaryBlue)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTokens.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.installed});

  final bool installed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: installed
            ? AppTokens.emerald.withValues(alpha: 0.12)
            : AppTokens.primaryBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        installed ? '已安装' : '可安装',
        style: TextStyle(
          color: installed ? AppTokens.emerald : AppTokens.primaryBlue,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MarketEmptyState extends StatelessWidget {
  const _MarketEmptyState({required this.loading, required this.onReset});

  final bool loading;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppTokens.divider),
        boxShadow: AppTokens.shadowSm(),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            loading ? Icons.hourglass_empty_rounded : Icons.search_off_rounded,
            color: AppTokens.primaryBlue,
            size: 38,
          ),
          const SizedBox(height: 12),
          Text(
            loading ? '正在加载插件市场...' : '没有匹配插件',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '换个关键词，或重置筛选查看全部模板',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTokens.textSecondary, fontSize: 12),
          ),
          if (!loading) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重置筛选'),
            ),
          ],
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: Colors.grey[700]),
      ),
    );
  }
}

class _MarketMetric extends StatelessWidget {
  const _MarketMetric({
    required this.value,
    required this.label,
    this.glass = true,
  });

  final String value;
  final String label;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: glass
            ? Colors.white.withValues(alpha: 0.14)
            : AppTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: glass
              ? Colors.white.withValues(alpha: 0.18)
              : AppTokens.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: glass ? Colors.white : AppTokens.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: glass
                  ? Colors.white.withValues(alpha: 0.76)
                  : AppTokens.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

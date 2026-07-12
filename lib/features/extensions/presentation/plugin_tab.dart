import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';
import 'package:box/features/extensions/market/data/plugin_market_manifest_repository.dart';
import 'package:box/novel/pages/source_manager/book_source_manager_page.dart';
import 'package:box/novel/pages/source_manager/book_source_diagnostic_page.dart';
import 'package:box/novel/pages/source_manager/book_source_model.dart';
import 'package:box/plugin_manager.dart';
import 'package:box/plugin_market/models/plugin_market_security.dart';
import 'package:box/plugin_market_page.dart';
import 'package:box/video_module.dart';
import 'package:http/http.dart' as http;

import 'widgets/extension_management_widgets.dart';
import 'widgets/plugin_card.dart';

class PluginTab extends StatefulWidget {
  const PluginTab({super.key});

  @override
  State<PluginTab> createState() => _PluginTabState();
}

class _PluginTabState extends State<PluginTab>
    with AutomaticKeepAliveClientMixin {
  final HomePluginHost _pluginHost = HomePluginHost.instance;

  // 资源计数
  int _bookSourceCount = 0;
  int _videoSourceCount = 0;

  // 撤销记录
  HomePlugin? _removedPlugin;
  Timer? _undoTimer;

  static const String _marketRemoteUrl = String.fromEnvironment(
    'PLUGIN_MARKET_URL',
    defaultValue: '',
  );

  static const String _marketChannelEnv = String.fromEnvironment(
    'PLUGIN_MARKET_CHANNEL',
    defaultValue: 'stable',
  );

  static const String _marketSignModeEnv = String.fromEnvironment(
    'PLUGIN_MARKET_SIGN_MODE',
    defaultValue: 'sha256',
  );

  static const String _marketSignSecret = String.fromEnvironment(
    'PLUGIN_MARKET_SIGN_SECRET',
    defaultValue: '',
  );

  static const bool _marketAllowUnsigned = bool.fromEnvironment(
    'PLUGIN_MARKET_ALLOW_UNSIGNED',
    defaultValue: false,
  );

  @override
  bool get wantKeepAlive => true;

  // ── 搜索 ──
  final TextEditingController _pluginSearchController = TextEditingController();
  String _pluginQuery = '';

  // ── 固定（Pin） ──
  Set<String> _pinnedPluginIds = {};
  static const String _pinStorageKey = 'pinned_plugin_ids';

  // ── 批量选择 ──
  bool _selectMode = false;
  final Set<String> _selectedPluginIds = {};

  // ── 市场推荐 ──
  List<MarketPluginTemplate> _marketTemplates = [];
  bool _marketLoading = true;

  @override
  void initState() {
    super.initState();
    _pluginHost.bootstrap();
    _loadSourceCounts();
    _loadPinned();
    _loadMarketRecommendations();
  }

  Future<void> _loadMarketRecommendations() async {
    try {
      final manifest = await PluginMarketManifestRepository.instance
          .loadManifest(
            fallbackTemplates: const [],
            channel: PluginMarketChannel.values.firstWhere(
              (c) => c.name == _marketChannelEnv,
              orElse: () => PluginMarketChannel.stable,
            ),
            security: PluginMarketSecurityConfig(
              mode: PluginMarketSignMode.values.firstWhere(
                (m) => m.name == _marketSignModeEnv,
                orElse: () => PluginMarketSignMode.sha256,
              ),
              secret: _marketSignSecret,
              allowUnsigned: _marketAllowUnsigned,
            ),
            remoteConfigUrl: _marketRemoteUrl.isNotEmpty
                ? _marketRemoteUrl
                : null,
          );
      // 取前 6 个高品质推荐
      final templates = manifest.templates
        ..sort((a, b) => a.sort.compareTo(b.sort));
      if (mounted) {
        setState(() {
          _marketTemplates = templates.take(6).toList();
          _marketLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _marketLoading = false);
    }
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selectedPluginIds.clear();
    });
  }

  void _toggleSelectPlugin(String pluginId) {
    setState(() {
      if (_selectedPluginIds.contains(pluginId)) {
        _selectedPluginIds.remove(pluginId);
      } else {
        _selectedPluginIds.add(pluginId);
      }
    });
  }

  void _selectAll(List<HomePlugin> plugins) {
    setState(() {
      _selectedPluginIds.addAll(plugins.map((p) => p.id));
    });
  }

  void _deselectAll() {
    setState(() => _selectedPluginIds.clear());
  }

  Future<void> _batchToggleEnabled(bool enabled) async {
    final ids = _selectedPluginIds.toList();
    var changedCount = 0;
    for (final id in ids) {
      final plugin = _pluginHost.findById(id);
      if (plugin == null) continue;
      // 跳过已经处于目标状态的插件
      if (plugin.enabled == enabled) continue;
      await _togglePluginEnabled(plugin, enabled);
      changedCount++;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled ? '已启用 $changedCount 个插件' : '已禁用 $changedCount 个插件',
        ),
      ),
    );
    _exitSelectMode();
  }

  Future<void> _batchUninstall() async {
    final ids = _selectedPluginIds.toList();
    // 过滤掉内置插件
    final uninstallIds = ids.where((id) {
      final plugin = _pluginHost.findById(id);
      if (plugin == null) return false;
      return !plugin.builtIn;
    }).toList();

    if (uninstallIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('内置插件不能卸载')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认卸载'),
        content: Text('确定卸载 ${uninstallIds.length} 个插件吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    for (final id in uninstallIds) {
      final plugin = _pluginHost.findById(id);
      if (plugin == null) continue;
      await _uninstallPlugin(plugin);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已卸载 ${uninstallIds.length} 个插件')));
    _exitSelectMode();
  }

  Widget _buildMarketRecommendations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: '推荐插件',
          subtitle: '${_marketTemplates.length} 个精选',
          icon: Icons.auto_awesome_rounded,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: _marketTemplates.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final tpl = _marketTemplates[index];
              final areaColor = _colorForAreaCode(tpl.areaCode);
              return GestureDetector(
                onTap: _openPluginMarket,
                child: Container(
                  width: 170,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppTokens.divider),
                    boxShadow: AppTokens.shadowSm(),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: areaColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(tpl.icon, color: areaColor, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              tpl.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: AppTokens.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tpl.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: Colors.grey.shade400,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _colorForAreaCode(String code) {
    switch (code) {
      case 'novel':
        return AppTokens.amber;
      case 'video':
        return AppTokens.primaryBlue;
      case 'music':
        return Colors.pink;
      case 'comic':
        return Colors.teal;
      case 'recommend':
        return Colors.deepPurple;
      case 'center':
        return Colors.blueGrey;
      default:
        return AppTokens.violet;
    }
  }

  Future<void> _loadPinned() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_pinStorageKey) ?? [];
      if (mounted) setState(() => _pinnedPluginIds = list.toSet());
    } catch (_) {}
  }

  Future<void> _savePinned() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_pinStorageKey, _pinnedPluginIds.toList());
    } catch (_) {}
  }

  void _togglePin(String pluginId) {
    setState(() {
      if (_pinnedPluginIds.contains(pluginId)) {
        _pinnedPluginIds.remove(pluginId);
      } else {
        _pinnedPluginIds.add(pluginId);
      }
    });
    _savePinned();
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    _pluginSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadSourceCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          prefs.getString('book_source_storage_key') ??
          prefs.getString('plugin_config_key') ??
          '[]';
      final list = (jsonDecode(raw) as List?) ?? [];
      final bookSources = list.where((e) {
        if (e is! Map) return false;
        final s = e as Map<String, dynamic>;
        final group = '${s['bookSourceGroup'] ?? ''}';
        return group.trim().isNotEmpty;
      }).length;
      if (mounted) setState(() => _bookSourceCount = bookSources);
    } catch (_) {
      _bookSourceCount = 0;
    }
    _videoSourceCount = 0;
  }

  int get _enabledPluginCount =>
      _pluginHost.allPlugins.where((p) => p.enabled).length;

  HomePluginArea _areaFromCode(String code) {
    switch (code.trim()) {
      case 'music':
        return HomePluginArea.music;
      case 'video':
        return HomePluginArea.video;
      case 'comic':
        return HomePluginArea.comic;
      case 'novel':
        return HomePluginArea.novel;
      case 'recommend':
      default:
        return HomePluginArea.recommend;
    }
  }

  HomePluginActionType _actionFromCode(String code) {
    switch (code.trim()) {
      case 'openDailyNews':
        return HomePluginActionType.openDailyNews;
      case 'openNovelList':
        return HomePluginActionType.openNovelList;
      case 'openVideoList':
        return HomePluginActionType.openVideoList;
      case 'openImageGenerator':
        return HomePluginActionType.openImageGenerator;
      case 'toast':
      default:
        return HomePluginActionType.toast;
    }
  }

  PluginMarketChannel _marketChannelFromEnv() {
    switch (_marketChannelEnv.trim().toLowerCase()) {
      case 'beta':
        return PluginMarketChannel.beta;
      case 'stable':
      default:
        return PluginMarketChannel.stable;
    }
  }

  PluginMarketSignMode _marketSignModeFromEnv() {
    switch (_marketSignModeEnv.trim().toLowerCase()) {
      case 'sha256':
        return PluginMarketSignMode.sha256;
      case 'hmac-sha256':
      case 'hmac_sha256':
      case 'hmacsha256':
        return PluginMarketSignMode.hmacSha256;
      case 'none':
      default:
        return PluginMarketSignMode.none;
    }
  }

  // ── Navigation ──

  Future<void> _openPluginMarket() async {
    final installedIds = _pluginHost.allPlugins
        .where((plugin) => !plugin.builtIn)
        .map((e) => e.id)
        .toSet();

    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PluginMarketPage(
            initialInstalledIds: installedIds,
            remoteConfigUrl: _marketRemoteUrl.trim().isEmpty
                ? null
                : _marketRemoteUrl.trim(),
            initialChannel: _marketChannelFromEnv(),
            securityConfig: PluginMarketSecurityConfig(
              mode: _marketSignModeFromEnv(),
              secret: _marketSignSecret,
              allowUnsigned: _marketAllowUnsigned,
            ),
            onInstall: (tpl) async {
              final config = HomeCustomPluginConfig(
                id: tpl.id,
                title: tpl.title,
                subtitle: tpl.subtitle,
                iconCodePoint: tpl.icon.codePoint,
                iconFontFamily: tpl.icon.fontFamily ?? 'MaterialIcons',
                iconFontPackage: tpl.icon.fontPackage,
                colorValue: tpl.color.toARGB32(),
                area: _areaFromCode(tpl.areaCode),
                actionType: _actionFromCode(tpl.actionCode),
                payload: tpl.payload,
                enabled: true,
                sort: tpl.sort,
                createdAt: DateTime.now().millisecondsSinceEpoch,
              );
              await _pluginHost.addCustomPlugin(config);
            },
            onUninstall: (pluginId) async {
              final plugin = _pluginHost.allPlugins
                  .where((p) => p.id == pluginId)
                  .firstOrNull;
              await _pluginHost.unregister(pluginId);
              if (plugin != null && mounted) _showUndoSnack(plugin);
            },
          ),
        ),
      );
    }
  }

  // ── Export / Import ──

  Future<void> _showExportJsonDialog() async {
    final jsonText = await _pluginHost.exportSnapshotJson(pretty: true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('导出插件 JSON'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '可复制保存，或用于导入到其它设备。',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
              const SizedBox(height: 10),
              Container(
                height: 320,
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F8FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    jsonText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: jsonText));
              if (!dialogCtx.mounted) return;
              ScaffoldMessenger.of(
                dialogCtx,
              ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('复制'),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportJsonDialog() async {
    final controller = TextEditingController();
    final urlController = TextEditingController();
    bool merge = false;
    bool useUrl = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(useUrl ? '从 URL 导入' : '导入插件 JSON'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildSegmentedButton(
                              '粘贴 JSON',
                              !useUrl,
                              () => setDialogState(() => useUrl = false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildSegmentedButton(
                              '从 URL 获取',
                              useUrl,
                              () => setDialogState(() => useUrl = true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (useUrl)
                        TextField(
                          controller: urlController,
                          decoration: const InputDecoration(
                            labelText: 'JSON URL',
                            hintText: 'https://example.com/plugins.json',
                            border: OutlineInputBorder(),
                          ),
                        )
                      else ...[
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () async {
                                final data = await Clipboard.getData(
                                  'text/plain',
                                );
                                final text = data?.text ?? '';
                                if (text.trim().isEmpty) {
                                  if (!ctx.mounted) return;
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('剪贴板为空')),
                                  );
                                  return;
                                }
                                controller.text = text;
                                controller
                                    .selection = TextSelection.fromPosition(
                                  TextPosition(offset: controller.text.length),
                                );
                              },
                              icon: const Icon(Icons.content_paste),
                              label: const Text('从剪贴板粘贴'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: controller,
                          minLines: 8,
                          maxLines: 14,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText:
                                '{"enabledMap": {...}, "customPlugins": [...]}',
                          ),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: merge,
                        title: const Text('合并导入（关闭则覆盖当前配置）'),
                        onChanged: (v) => setDialogState(() => merge = v),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(dialogCtx);
                    final navigator = Navigator.of(dialogCtx);
                    try {
                      String raw;
                      if (useUrl) {
                        final url = urlController.text.trim();
                        if (url.isEmpty) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('请输入 URL')),
                          );
                          return;
                        }
                        final resp = await http
                            .get(Uri.parse(url))
                            .timeout(const Duration(seconds: 10));
                        if (resp.statusCode != 200) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('获取失败：HTTP ${resp.statusCode}'),
                            ),
                          );
                          return;
                        }
                        raw = resp.body;
                      } else {
                        raw = controller.text.trim();
                        if (raw.isEmpty) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('请输入 JSON')),
                          );
                          return;
                        }
                      }
                      await _pluginHost.importSnapshotJson(raw, merge: merge);
                      navigator.pop();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(merge ? '导入成功（已合并）' : '导入成功（已覆盖）'),
                        ),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('导入失败：$e')),
                      );
                    }
                  },
                  child: const Text('开始导入'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    urlController.dispose();
  }

  Widget _buildSegmentedButton(
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected
            ? AppTokens.violet.withValues(alpha: 0.08)
            : null,
        side: BorderSide(
          color: selected ? AppTokens.violet : AppTokens.divider,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? AppTokens.violet : AppTokens.textSecondary,
        ),
      ),
    );
  }

  // ── Plugin actions ──

  Future<void> _runPlugin(BuildContext context, HomePlugin plugin) async {
    try {
      await plugin.onTap(context);
    } catch (e) {
      if (!context.mounted) return;
      _showSnack(context, '插件执行失败: $e');
    }
  }

  Future<void> _togglePluginEnabled(HomePlugin plugin, bool enabled) async {
    await _pluginHost.toggleEnabled(plugin.id, enabled);
  }

  Future<void> _uninstallPlugin(HomePlugin plugin) async {
    await _pluginHost.unregister(plugin.id);
    if (mounted) _showUndoSnack(plugin);
  }

  void _showUndoSnack(HomePlugin plugin) {
    _removedPlugin = plugin;
    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(seconds: 5), () {
      _removedPlugin = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已卸载 "${plugin.title}"'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            _undoTimer?.cancel();
            if (_removedPlugin != null) {
              final idx = _pluginHost.allPlugins.indexWhere(
                (p) => p.id == _removedPlugin!.id,
              );
              if (idx < 0) {
                await _pluginHost.register(_removedPlugin!);
              }
              _removedPlugin = null;
            }
          },
        ),
      ),
    );
  }

  // ── Navigation helpers ──

  void _openBookSourceManager() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BookSourceManagerPage()),
    );
  }

  void _openVideoSourceCenter() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VideoListPage()),
    );
  }

  void _openDiagnostics() {
    final emptySource = BookSourceModel(
      rawJson: const {},
      bookSourceName: '诊断模式',
      bookSourceUrl: '',
      bookSourceGroup: '',
      searchUrl: '',
      exploreUrl: '',
      enabled: false,
      weight: 0,
      customOrder: 0,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookSourceDiagnosticPage(source: emptySource),
      ),
    );
  }

  // ── Build ──

  Widget _buildManagementGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: '快捷入口',
          subtitle: '资源规则管理 · 诊断',
          icon: Icons.rocket_launch_rounded,
        ),
        const SizedBox(height: 10),
        // 2×2 网格布局
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: [
            // 书源管理 — 白色卡片
            ExtensionManagementTile(
              title: '书源管理',
              subtitle: '$_bookSourceCount 个规则',
              icon: Icons.menu_book_rounded,
              color: AppTokens.amber,
              count: _bookSourceCount,
              onTap: _openBookSourceManager,
            ),
            // 片源管理 — 白色卡片
            ExtensionManagementTile(
              title: '片源管理',
              subtitle: '影视源 · 播放链路',
              icon: Icons.live_tv_rounded,
              color: AppTokens.primaryBlue,
              onTap: _openVideoSourceCenter,
            ),
            // 导入配置 — 渐变卡片
            ExtensionManagementTile(
              title: '导入配置',
              subtitle: 'JSON 粘贴 · URL 拉取',
              icon: Icons.download_for_offline_rounded,
              color: AppTokens.emerald,
              gradient: LinearGradient(
                colors: [
                  AppTokens.emerald.withValues(alpha: 0.92),
                  AppTokens.emerald.withValues(alpha: 0.68),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              primary: true,
              onTap: _showImportJsonDialog,
            ),
            // 运行诊断 — 渐变卡片
            ExtensionManagementTile(
              title: '运行诊断',
              subtitle: '书源检测 · 规则调试',
              icon: Icons.health_and_safety_outlined,
              color: AppTokens.rose,
              gradient: LinearGradient(
                colors: [
                  AppTokens.rose.withValues(alpha: 0.92),
                  AppTokens.rose.withValues(alpha: 0.68),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              primary: true,
              onTap: _openDiagnostics,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return AppPageScaffold(
      maxContentWidth: 720,
      child: SafeValueListenableBuilder<List<HomePlugin>>(
        valueListenable: _pluginHost.listenable,
        builder: (context, plugins, _) {
          final enabledList = plugins.where((p) => p.enabled).toList()
            ..sort((a, b) {
              final aPinned = _pinnedPluginIds.contains(a.id);
              final bPinned = _pinnedPluginIds.contains(b.id);
              if (aPinned != bPinned) return aPinned ? -1 : 1;
              return a.sort.compareTo(b.sort);
            });
          final disabledList = plugins.where((p) => !p.enabled).toList()
            ..sort((a, b) {
              final aPinned = _pinnedPluginIds.contains(a.id);
              final bPinned = _pinnedPluginIds.contains(b.id);
              if (aPinned != bPinned) return aPinned ? -1 : 1;
              return a.sort.compareTo(b.sort);
            });

          final query = _pluginQuery.toLowerCase().trim();
          List<HomePlugin> filteredEnabled = enabledList;
          List<HomePlugin> filteredDisabled = disabledList;
          if (query.isNotEmpty) {
            filteredEnabled = enabledList
                .where(
                  (p) =>
                      p.title.toLowerCase().contains(query) ||
                      p.subtitle.toLowerCase().contains(query) ||
                      p.area.label.toLowerCase().contains(query),
                )
                .toList();
            filteredDisabled = disabledList
                .where(
                  (p) =>
                      p.title.toLowerCase().contains(query) ||
                      p.subtitle.toLowerCase().contains(query) ||
                      p.area.label.toLowerCase().contains(query),
                )
                .toList();
          }
          final hasResult =
              filteredEnabled.isNotEmpty || filteredDisabled.isNotEmpty;

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              16,
              10,
              16,
              AppTokens.pageBottomPadding + 32,
            ),
            children: [
              ExtensionHeroCard(
                pluginCount: plugins.length,
                enabledCount: _enabledPluginCount,
                bookSourceCount: _bookSourceCount,
                videoSourceCount: _videoSourceCount,
                onOpenMarket: _openPluginMarket,
                onImportJson: _showImportJsonDialog,
                onExportJson: _showExportJsonDialog,
              ),
              const SizedBox(height: 16),
              _buildManagementGrid(),
              const SizedBox(height: 20),
              // ── 市场推荐 ──
              if (!_selectMode &&
                  !_marketLoading &&
                  _marketTemplates.isNotEmpty)
                _buildMarketRecommendations(),
              const SizedBox(height: 12),
              // 操作栏：搜索 + 批量按钮
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _pluginSearchController,
                        onChanged: (v) => setState(() => _pluginQuery = v),
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: '搜索插件名称、描述、区域…',
                          hintStyle: const TextStyle(
                            color: AppTokens.textSecondary,
                            fontSize: 12.5,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: AppTokens.violet,
                          ),
                          suffixIcon: _pluginQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 18,
                                    color: AppTokens.textSecondary,
                                  ),
                                  onPressed: () {
                                    _pluginSearchController.clear();
                                    setState(() => _pluginQuery = '');
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26),
                            borderSide: const BorderSide(
                              color: Color(0xFFE7ECF5),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26),
                            borderSide: const BorderSide(
                              color: Color(0xFFE7ECF5),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26),
                            borderSide: const BorderSide(
                              color: AppTokens.violet,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8F9FE),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 批量模式切换
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: _selectMode
                          ? AppTokens.violet.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      tooltip: _selectMode ? '退出批量' : '批量操作',
                      onPressed: () {
                        setState(() => _selectMode = !_selectMode);
                        if (!_selectMode) _selectedPluginIds.clear();
                      },
                      icon: Icon(
                        _selectMode
                            ? Icons.checklist_rounded
                            : Icons.checklist_rtl_outlined,
                        size: 22,
                        color: _selectMode
                            ? AppTokens.violet
                            : AppTokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // ── 批量操作栏 ──
              if (_selectMode)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTokens.violet.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppTokens.violet.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    children: [
                      // 计数
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTokens.violet.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '已选 ${_selectedPluginIds.length}',
                          style: const TextStyle(
                            color: AppTokens.violet,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppTokens.primaryBlue,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _selectAll([
                          ...filteredEnabled,
                          ...filteredDisabled,
                        ]),
                        icon: const Icon(Icons.select_all_rounded, size: 16),
                        label: const Text('全选', style: TextStyle(fontSize: 12)),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppTokens.textSecondary,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _deselectAll,
                        icon: const Icon(Icons.deselect_rounded, size: 16),
                        label: const Text('取消', style: TextStyle(fontSize: 12)),
                      ),
                      const Spacer(),
                      // 启用
                      if (_selectedPluginIds.isNotEmpty) ...[
                        _BatchActionButton(
                          icon: Icons.check_circle_outline_rounded,
                          label: '启用',
                          color: AppTokens.emerald,
                          onTap: () => _batchToggleEnabled(true),
                        ),
                        const SizedBox(width: 4),
                        _BatchActionButton(
                          icon: Icons.pause_circle_outline_rounded,
                          label: '禁用',
                          color: AppTokens.amber,
                          onTap: () => _batchToggleEnabled(false),
                        ),
                        const SizedBox(width: 4),
                        _BatchActionButton(
                          icon: Icons.delete_outline_rounded,
                          label: '卸载',
                          color: AppTokens.rose,
                          onTap: _batchUninstall,
                        ),
                      ],
                    ],
                  ),
                ),
              if (!hasResult)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      '没有匹配的插件',
                      style: TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
              else ...[
                _PluginStatusSection(
                  title: '已启用',
                  icon: Icons.check_circle_rounded,
                  iconColor: AppTokens.emerald,
                  plugins: filteredEnabled,
                  onRunPlugin: _runPlugin,
                  onToggleEnabled: _togglePluginEnabled,
                  onUninstall: _uninstallPlugin,
                  totalCount: enabledList.length,
                  pinnedPluginIds: _pinnedPluginIds,
                  onPinToggle: _togglePin,
                  selectMode: _selectMode,
                  selectedPluginIds: _selectedPluginIds,
                  onSelectToggle: _toggleSelectPlugin,
                ),
                if (filteredDisabled.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _PluginStatusSection(
                    title: '已禁用',
                    icon: Icons.pause_circle_outline_rounded,
                    iconColor: AppTokens.textTertiary,
                    plugins: filteredDisabled,
                    onRunPlugin: _runPlugin,
                    onToggleEnabled: _togglePluginEnabled,
                    onUninstall: _uninstallPlugin,
                    totalCount: disabledList.length,
                    pinnedPluginIds: _pinnedPluginIds,
                    onPinToggle: _togglePin,
                    selectMode: _selectMode,
                    selectedPluginIds: _selectedPluginIds,
                    onSelectToggle: _toggleSelectPlugin,
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

Future<void> _showSnack(BuildContext context, String text) async {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

// ═══════════════════════════════════════════════════════════════════
// _PluginStatusSection — 按启用/禁用状态分组的可折叠插件列表
// ═══════════════════════════════════════════════════════════════════

class _PluginStatusSection extends StatefulWidget {
  const _PluginStatusSection({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.plugins,
    required this.onRunPlugin,
    required this.onToggleEnabled,
    required this.onUninstall,
    required this.totalCount,
    required this.pinnedPluginIds,
    required this.onPinToggle,
    this.selectMode = false,
    this.selectedPluginIds = const {},
    this.onSelectToggle,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final List<HomePlugin> plugins;
  final Future<void> Function(BuildContext context, HomePlugin plugin)
  onRunPlugin;
  final Future<void> Function(HomePlugin plugin, bool enabled) onToggleEnabled;
  final Future<void> Function(HomePlugin plugin) onUninstall;
  final int totalCount;
  final Set<String> pinnedPluginIds;
  final void Function(String pluginId) onPinToggle;
  final bool selectMode;
  final Set<String> selectedPluginIds;
  final void Function(String pluginId)? onSelectToggle;

  @override
  State<_PluginStatusSection> createState() => _PluginStatusSectionState();
}

class _PluginStatusSectionState extends State<_PluginStatusSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(widget.icon, size: 20, color: widget.iconColor),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: AppTokens.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: widget.iconColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  ),
                  child: Text(
                    '${widget.plugins.length}/${widget.totalCount}',
                    style: TextStyle(
                      color: widget.iconColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.expand_more_rounded,
                    color: AppTokens.textSecondary,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Column(
            children: List.generate(widget.plugins.length, (i) {
              final plugin = widget.plugins[i];
              return _StaggeredItem(
                index: i,
                child: PluginCard(
                  plugin: plugin,
                  isPinned: widget.pinnedPluginIds.contains(plugin.id),
                  onPinToggle: widget.onPinToggle,
                  selectMode: widget.selectMode,
                  isSelected: widget.selectedPluginIds.contains(plugin.id),
                  onSelectToggle: widget.onSelectToggle,
                  onRunPlugin: widget.onRunPlugin,
                  onToggleEnabled: widget.onToggleEnabled,
                  onUninstall: widget.onUninstall,
                ),
              );
            }),
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState: _expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// _StaggeredItem — 入场错开动画
// ═══════════════════════════════════════════════════════════════════

/// 入场错开动画 — 淡入 + 上滑
class _StaggeredItem extends StatefulWidget {
  const _StaggeredItem({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<_StaggeredItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _opacity = _ctrl;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    Future.delayed(Duration(milliseconds: widget.index * 50), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// _BatchActionButton — 批量操作小按钮
// ═══════════════════════════════════════════════════════════════════

class _BatchActionButton extends StatelessWidget {
  const _BatchActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';
import 'package:box/novel/pages/source_manager/book_source_manager_page.dart';
import 'package:box/plugin_manager.dart';
import 'package:box/plugin_market/models/plugin_market_security.dart';
import 'package:box/plugin_market_page.dart';
import 'package:box/video_module.dart';

import 'widgets/extension_management_widgets.dart';

class PluginTab extends StatefulWidget {
  const PluginTab({super.key});

  @override
  State<PluginTab> createState() => _PluginTabState();
}

class _PluginTabState extends State<PluginTab>
    with AutomaticKeepAliveClientMixin {
  final HomePluginHost _pluginHost = HomePluginHost.instance;

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

  @override
  void initState() {
    super.initState();
    _pluginHost.bootstrap();
  }

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

  Color _colorForArea(HomePluginArea area) {
    switch (area) {
      case HomePluginArea.recommend:
        return Colors.deepPurple;
      case HomePluginArea.music:
        return Colors.pink;
      case HomePluginArea.video:
        return Colors.indigo;
      case HomePluginArea.comic:
        return Colors.teal;
      case HomePluginArea.novel:
        return Colors.orange;
      case HomePluginArea.center:
        return Colors.blueGrey;
    }
  }

  IconData _iconForArea(HomePluginArea area) {
    switch (area) {
      case HomePluginArea.recommend:
        return Icons.local_fire_department_outlined;
      case HomePluginArea.music:
        return Icons.music_note_outlined;
      case HomePluginArea.video:
        return Icons.play_circle_outline;
      case HomePluginArea.comic:
        return Icons.image_outlined;
      case HomePluginArea.novel:
        return Icons.menu_book_outlined;
      case HomePluginArea.center:
        return Icons.extension_outlined;
    }
  }

  Future<void> _openPluginMarket() async {
    final installedIds = _pluginHost.allPlugins
        .where((plugin) => !plugin.builtIn)
        .map((e) => e.id)
        .toSet();

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
            await _pluginHost.unregister(pluginId);
          },
        ),
      ),
    );
  }

  Future<void> _showAddPluginDialog() async {
    final titleController = TextEditingController();
    final subController = TextEditingController();
    final payloadController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    HomePluginArea selectedArea = HomePluginArea.recommend;
    HomePluginActionType selectedAction = HomePluginActionType.toast;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final payloadHint = selectedAction == HomePluginActionType.toast
                ? '弹窗内容（为空则默认）'
                : '可选参数（当前动作可忽略）';

            return AlertDialog(
              title: const Text('新增自定义插件'),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: titleController,
                          decoration: const InputDecoration(
                            labelText: '插件名称',
                            hintText: '例如：我的导航',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return '请输入插件名称';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: subController,
                          decoration: const InputDecoration(
                            labelText: '插件描述',
                            hintText: '一句简短描述',
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<HomePluginArea>(
                          initialValue: selectedArea,
                          decoration: const InputDecoration(labelText: '挂载区域'),
                          items: HomePluginArea.values
                              .where((e) => e != HomePluginArea.center)
                              .map(
                                (area) => DropdownMenuItem<HomePluginArea>(
                                  value: area,
                                  child: Text(area.label),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setDialogState(() => selectedArea = v);
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<HomePluginActionType>(
                          initialValue: selectedAction,
                          decoration: const InputDecoration(labelText: '点击动作'),
                          items: HomePluginActionType.values
                              .map(
                                (action) =>
                                    DropdownMenuItem<HomePluginActionType>(
                                      value: action,
                                      child: Text(action.label),
                                    ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setDialogState(() => selectedAction = v);
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: payloadController,
                          decoration: InputDecoration(
                            labelText: '动作参数',
                            hintText: payloadHint,
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
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
                    if (!formKey.currentState!.validate()) return;

                    final title = titleController.text.trim();
                    final sub = subController.text.trim();
                    final payload = payloadController.text.trim();
                    final id =
                        'custom_${DateTime.now().millisecondsSinceEpoch}';

                    final icon = _iconForArea(selectedArea);
                    final color = _colorForArea(selectedArea);

                    final config = HomeCustomPluginConfig(
                      id: id,
                      title: title,
                      subtitle: sub.isEmpty ? '自定义插件' : sub,
                      iconCodePoint: icon.codePoint,
                      iconFontFamily: icon.fontFamily ?? 'MaterialIcons',
                      iconFontPackage: icon.fontPackage,
                      colorValue: color.toARGB32(),
                      area: selectedArea,
                      actionType: selectedAction,
                      payload: payload,
                      enabled: true,
                      sort: 9999,
                      createdAt: DateTime.now().millisecondsSinceEpoch,
                    );

                    await _pluginHost.addCustomPlugin(config);

                    if (!dialogCtx.mounted) return;
                    Navigator.pop(dialogCtx);
                  },
                  child: const Text('添加'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    subController.dispose();
    payloadController.dispose();
  }

  Future<void> _showExportJsonDialog() async {
    final jsonText = await _pluginHost.exportSnapshotJson(pretty: true);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
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
                final messenger = ScaffoldMessenger.of(dialogCtx);
                await Clipboard.setData(ClipboardData(text: jsonText));
                messenger.showSnackBar(
                  const SnackBar(content: Text('已复制到剪贴板')),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('复制'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showImportJsonDialog() async {
    final controller = TextEditingController();
    bool merge = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('导入插件 JSON'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '粘贴之前导出的 JSON 配置：',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(ctx);
                              final data = await Clipboard.getData(
                                'text/plain',
                              );
                              final text = data?.text ?? '';
                              if (text.trim().isEmpty) {
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('剪贴板为空')),
                                );
                                return;
                              }
                              controller.text = text;
                              controller.selection = TextSelection.fromPosition(
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
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: merge,
                        title: const Text('合并导入（关闭则覆盖当前配置）'),
                        onChanged: (v) {
                          setDialogState(() => merge = v);
                        },
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
                    final raw = controller.text.trim();
                    if (raw.isEmpty) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('请输入 JSON')),
                      );
                      return;
                    }

                    try {
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
  }

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

  void _showExtensionTip(String title) {
    _showSnack(context, '$title 后续会集中放在扩展中心');
  }

  Widget _buildPluginEntryCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: '插件工作台',
          subtitle: '市场模板、手动新增、已装管理分离展示',
          icon: Icons.extension_rounded,
        ),
        const SizedBox(height: 10),
        ExtensionManagementTile(
          title: '插件市场',
          subtitle: 'Stable / Beta 模板、验签、批量安装',
          icon: Icons.storefront_rounded,
          color: AppTokens.violet,
          primary: true,
          onTap: _openPluginMarket,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ExtensionManagementTile(
                title: '新增插件',
                subtitle: '自定义入口和动作',
                icon: Icons.add_circle_rounded,
                color: AppTokens.primaryBlue,
                onTap: _showAddPluginDialog,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ExtensionManagementTile(
                title: '已装插件',
                subtitle: '下方按区域启用/卸载',
                icon: Icons.inventory_2_outlined,
                color: AppTokens.emerald,
                onTap: () => _showSnack(context, '已装插件在下方管理列表中'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const AppSectionHeader(
          title: '资源规则中心',
          subtitle: '书源 / 片源以管理入口呈现，不再像普通功能卡片',
          icon: Icons.rule_folder_rounded,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ExtensionManagementTile(
                title: '书源管理',
                subtitle: '小说规则 / 导入 / 启用状态',
                icon: Icons.menu_book_rounded,
                color: AppTokens.amber,
                onTap: _openBookSourceManager,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ExtensionManagementTile(
                title: '片源管理',
                subtitle: '影视源 / 搜索 / 播放链路',
                icon: Icons.live_tv_rounded,
                color: AppTokens.primaryBlue,
                onTap: _openVideoSourceCenter,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const AppSectionHeader(
          title: '数据备份',
          subtitle: '插件配置 JSON 导入导出，迁移到其它设备',
          icon: Icons.backup_rounded,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ExtensionManagementTile(
                title: '导入 JSON',
                subtitle: '合并或覆盖当前配置',
                icon: Icons.download_for_offline_rounded,
                color: AppTokens.emerald,
                onTap: _showImportJsonDialog,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ExtensionManagementTile(
                title: '导出 JSON',
                subtitle: '复制当前插件快照',
                icon: Icons.upload_file_rounded,
                color: AppTokens.cyan,
                onTap: _showExportJsonDialog,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const AppSectionHeader(
          title: '开发诊断',
          subtitle: '日志、错误、运行排查入口保留但不干扰日常操作',
          icon: Icons.bug_report_rounded,
        ),
        const SizedBox(height: 10),
        ExtensionManagementTile(
          title: '运行诊断',
          subtitle: '查看插件执行失败、市场拉取和资源规则问题',
          icon: Icons.health_and_safety_outlined,
          color: AppTokens.rose,
          onTap: () => _showExtensionTip('运行诊断'),
        ),
      ],
    );
  }

  Future<void> _runPlugin(BuildContext context, HomePlugin plugin) async {
    try {
      await plugin.onTap(context);
    } catch (e) {
      if (!context.mounted) return;
      await _showSnack(context, '插件执行失败: $e');
    }
  }

  Future<void> _togglePluginEnabled(HomePlugin plugin, bool enabled) async {
    await _pluginHost.toggleEnabled(plugin.id, enabled);
  }

  Future<void> _uninstallPlugin(HomePlugin plugin) async {
    await _pluginHost.unregister(plugin.id);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return AppPageScaffold(
      child: ValueListenableBuilder<List<HomePlugin>>(
        valueListenable: _pluginHost.listenable,
        builder: (context, plugins, _) {
          final grouped = <HomePluginArea, List<HomePlugin>>{
            for (final area in HomePluginArea.values) area: <HomePlugin>[],
          };

          for (final plugin in plugins) {
            grouped[plugin.area]!.add(plugin);
          }

          for (final area in grouped.keys) {
            grouped[area]!.sort((a, b) {
              final c = a.sort.compareTo(b.sort);
              if (c != 0) return c;
              return a.title.compareTo(b.title);
            });
          }

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
                onOpenMarket: _openPluginMarket,
                onImportJson: _showImportJsonDialog,
              ),
              const SizedBox(height: 16),
              _buildPluginEntryCards(),
              const SizedBox(height: 18),
              for (final area in HomePluginArea.values)
                ExtensionPluginSection(
                  area: area,
                  plugins: grouped[area]!,
                  onRunPlugin: _runPlugin,
                  onToggleEnabled: _togglePluginEnabled,
                  onUninstall: _uninstallPlugin,
                ),
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

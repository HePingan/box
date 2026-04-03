import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'plugin_manager.dart';
import 'plugin_market_page.dart';

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
    defaultValue: 'none',
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
          remoteConfigUrl:
              _marketRemoteUrl.trim().isEmpty ? null : _marketRemoteUrl.trim(),
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
              colorValue: tpl.color.value,
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
                          value: selectedArea,
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
                          value: selectedAction,
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
                    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';

                    final icon = _iconForArea(selectedArea);
                    final color = _colorForArea(selectedArea);

                    final config = HomeCustomPluginConfig(
                      id: id,
                      title: title,
                      subtitle: sub.isEmpty ? '自定义插件' : sub,
                      iconCodePoint: icon.codePoint,
                      iconFontFamily: icon.fontFamily ?? 'MaterialIcons',
                      iconFontPackage: icon.fontPackage,
                      colorValue: color.value,
                      area: selectedArea,
                      actionType: selectedAction,
                      payload: payload,
                      enabled: true,
                      sort: 9999,
                      createdAt: DateTime.now().millisecondsSinceEpoch,
                    );

                    await _pluginHost.addCustomPlugin(config);

                    if (!mounted) return;
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
                await Clipboard.setData(ClipboardData(text: jsonText));
                if (!mounted) return;
                await _showSnack(context, '已复制到剪贴板');
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
                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              final data = await Clipboard.getData('text/plain');
                              final text = data?.text ?? '';
                              if (text.trim().isEmpty) {
                                if (!mounted) return;
                                await _showSnack(context, '剪贴板为空');
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
                          hintText: '{"enabledMap": {...}, "customPlugins": [...]}',
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
                    final raw = controller.text.trim();
                    if (raw.isEmpty) {
                      await _showSnack(context, '请输入 JSON');
                      return;
                    }

                    try {
                      await _pluginHost.importSnapshotJson(raw, merge: merge);
                      if (!mounted) return;
                      Navigator.pop(dialogCtx);
                      await _showSnack(
                        context,
                        merge ? '导入成功（已合并）' : '导入成功（已覆盖）',
                      );
                    } catch (e) {
                      await _showSnack(context, '导入失败：$e');
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

  Widget _buildPluginSection(
    BuildContext context,
    HomePluginArea area,
    List<HomePlugin> plugins,
  ) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(area.icon, size: 18, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Text(
                  area.label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${plugins.length} 个',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (plugins.isEmpty)
              Text(
                '暂无插件',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              )
            else
              Column(
                children: plugins.map((plugin) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      onTap: () async {
                        try {
                          await plugin.onTap(context);
                        } catch (e) {
                          await _showSnack(context, '插件执行失败: $e');
                        }
                      },
                      leading: CircleAvatar(
                        backgroundColor: plugin.color.withOpacity(0.15),
                        child: Icon(plugin.icon, color: plugin.color, size: 18),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              plugin.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (plugin.builtIn)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                '内置',
                                style: TextStyle(fontSize: 10),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        plugin.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: SizedBox(
                        width: plugin.builtIn ? 62 : 102,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: plugin.enabled,
                              onChanged: (value) async {
                                await _pluginHost.toggleEnabled(
                                  plugin.id,
                                  value,
                                );
                              },
                            ),
                            if (!plugin.builtIn)
                              IconButton(
                                tooltip: '删除',
                                onPressed: () async {
                                  await _pluginHost.unregister(plugin.id);
                                },
                                icon: const Icon(Icons.delete_outline),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('插件中心'),
      ),
      body: SafeArea(
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '插件中心',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '支持运行时注册、持久化，以及 JSON 导入导出。',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: _showAddPluginDialog,
                              icon: const Icon(Icons.add),
                              label: const Text('新增自定义插件'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _openPluginMarket,
                              icon: const Icon(Icons.storefront_outlined),
                              label: const Text('插件市场'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _showExportJsonDialog,
                              icon: const Icon(Icons.upload_file_outlined),
                              label: const Text('导出 JSON'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _showImportJsonDialog,
                              icon: const Icon(Icons.download_for_offline_outlined),
                              label: const Text('导入 JSON'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await _pluginHost.restoreDefaults();
                                if (!mounted) return;
                                await _showSnack(context, '已恢复默认插件');
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('恢复默认'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                for (final area in HomePluginArea.values)
                  _buildPluginSection(context, area, grouped[area]!),
              ],
            );
          },
        ),
      ),
    );
  }
}

Future<void> _showSnack(BuildContext context, String text) async {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text)),
  );
}
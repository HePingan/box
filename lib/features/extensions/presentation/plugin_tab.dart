import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/novel/pages/source_manager/book_source_manager_page.dart';
import 'package:box/plugin_manager.dart';
import 'package:box/plugin_market/models/plugin_market_security.dart';
import 'package:box/plugin_market_page.dart';
import 'package:box/video_module.dart';

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

  Widget _buildPluginHero(int pluginCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF7C3AED), Color(0xFFFF4D8D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.24),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: const Text(
                  'EXT HUB 2.1',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            '扩展控制台',
            style: TextStyle(
              color: Colors.white,
              fontSize: 29,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'B2-A 四页统一 · 插件 / 资源规则 / 备份 / 诊断四区收纳',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.84),
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _PluginHeroMetric(value: '$pluginCount', label: '插件'),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: _PluginHeroMetric(value: '书源', label: '小说规则'),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: _PluginHeroMetric(value: '片源', label: '影视规则'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
            ),
            child: const Row(
              children: [
                Icon(Icons.tune_rounded, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '四页统一后：市场、规则、备份、诊断保持首屏优先',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openPluginMarket,
                  icon: const Icon(Icons.storefront_rounded),
                  label: const Text('插件市场'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF7C3AED),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showImportJsonDialog,
                  icon: const Icon(Icons.download_for_offline_rounded),
                  label: const Text('导入 JSON'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.55),
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
        _ManagementTile(
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
              child: _ManagementTile(
                title: '新增插件',
                subtitle: '自定义入口和动作',
                icon: Icons.add_circle_rounded,
                color: AppTokens.primaryBlue,
                onTap: _showAddPluginDialog,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ManagementTile(
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
              child: _ManagementTile(
                title: '书源管理',
                subtitle: '小说规则 / 导入 / 启用状态',
                icon: Icons.menu_book_rounded,
                color: AppTokens.amber,
                onTap: _openBookSourceManager,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ManagementTile(
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
              child: _ManagementTile(
                title: '导入 JSON',
                subtitle: '合并或覆盖当前配置',
                icon: Icons.download_for_offline_rounded,
                color: AppTokens.emerald,
                onTap: _showImportJsonDialog,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ManagementTile(
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
        _ManagementTile(
          title: '运行诊断',
          subtitle: '查看插件执行失败、市场拉取和资源规则问题',
          icon: Icons.health_and_safety_outlined,
          color: AppTokens.rose,
          onTap: () => _showExtensionTip('运行诊断'),
        ),
      ],
    );
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

  String _areaHubTitle(HomePluginArea area) {
    switch (area) {
      case HomePluginArea.recommend:
        return '首页推荐扩展';
      case HomePluginArea.music:
        return '音乐能力扩展';
      case HomePluginArea.video:
        return '影视能力扩展';
      case HomePluginArea.comic:
        return '漫画能力扩展';
      case HomePluginArea.novel:
        return '小说能力扩展';
      case HomePluginArea.center:
        return '中心控制扩展';
    }
  }

  String _areaHubSubtitle(HomePluginArea area) {
    switch (area) {
      case HomePluginArea.recommend:
        return '展示在首页推荐区的快捷能力';
      case HomePluginArea.music:
        return '音乐搜索、歌单和音频相关扩展';
      case HomePluginArea.video:
        return '影视搜索、片源和播放链路扩展';
      case HomePluginArea.comic:
        return '漫画收藏、搜索和榜单扩展';
      case HomePluginArea.novel:
        return '小说书架、书源和阅读扩展';
      case HomePluginArea.center:
        return '配置、诊断和系统级扩展';
    }
  }

  Widget _buildPluginSection(
    BuildContext context,
    HomePluginArea area,
    List<HomePlugin> plugins,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTokens.divider),
        boxShadow: AppTokens.shadowSm(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _colorForArea(area).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(area.icon, size: 18, color: _colorForArea(area)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _areaHubTitle(area),
                      style: const TextStyle(
                        color: AppTokens.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _areaHubSubtitle(area),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _PluginStatusChip(
                text: '${plugins.length} 个',
                color: _colorForArea(area),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (plugins.isEmpty)
            const AppEmptyState(
              title: '暂无插件',
              message: '可从插件市场安装，或新增自定义插件。',
              icon: Icons.extension_off_rounded,
              height: 118,
            )
          else
            Column(
              children: plugins.map((plugin) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: plugin.enabled
                        ? plugin.color.withValues(alpha: 0.04)
                        : AppTokens.surfaceMuted,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: plugin.enabled
                          ? plugin.color.withValues(alpha: 0.18)
                          : AppTokens.divider,
                    ),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          try {
                            await plugin.onTap(context);
                          } catch (e) {
                            if (!context.mounted) return;
                            await _showSnack(context, '插件执行失败: $e');
                          }
                        },
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: plugin.color.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            plugin.icon,
                            color: plugin.color,
                            size: 19,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            try {
                              await plugin.onTap(context);
                            } catch (e) {
                              if (!context.mounted) return;
                              await _showSnack(context, '插件执行失败: $e');
                            }
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      plugin.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppTokens.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _PluginStatusChip(
                                    text: plugin.enabled ? '已启用' : '未启用',
                                    color: plugin.enabled
                                        ? AppTokens.emerald
                                        : AppTokens.textTertiary,
                                  ),
                                  if (plugin.builtIn) ...[
                                    const SizedBox(width: 4),
                                    const _PluginStatusChip(
                                      text: '内置',
                                      color: AppTokens.primaryBlue,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                plugin.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTokens.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Switch.adaptive(
                        value: plugin.enabled,
                        onChanged: (value) async {
                          await _pluginHost.toggleEnabled(plugin.id, value);
                        },
                      ),
                      if (!plugin.builtIn)
                        IconButton(
                          tooltip: '卸载插件',
                          onPressed: () async {
                            await _pluginHost.unregister(plugin.id);
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                          color: AppTokens.rose,
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
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
              padding: const EdgeInsets.fromLTRB(
                16,
                10,
                16,
                AppTokens.pageBottomPadding + 32,
              ),
              children: [
                _buildPluginHero(plugins.length),
                const SizedBox(height: 16),
                _buildPluginEntryCards(),
                const SizedBox(height: 18),
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

class _ManagementTile extends StatelessWidget {
  const _ManagementTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.primary = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? Colors.white : AppTokens.textPrimary;
    final muted = primary
        ? Colors.white.withValues(alpha: 0.78)
        : AppTokens.textSecondary;
    final decoration = primary
        ? BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.72)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppTokens.shadowSm(color: color),
          )
        : BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTokens.divider),
            boxShadow: AppTokens.shadowSm(color: color),
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(primary ? 22 : 20),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: primary ? 92 : 104),
          padding: const EdgeInsets.all(14),
          decoration: decoration,
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: primary
                      ? Colors.white.withValues(alpha: 0.18)
                      : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: primary ? Colors.white : color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: primary ? Colors.white : AppTokens.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PluginStatusChip extends StatelessWidget {
  const _PluginStatusChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PluginHeroMetric extends StatelessWidget {
  const _PluginHeroMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showSnack(BuildContext context, String text) async {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

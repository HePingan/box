// lib/features/home/presentation/quick_action_picker_page.dart
//
// 「快捷入口」自选页：从已注册插件里勾选要摆到首页的入口，并可拖动排序。
//
// 设计取舍：
//  - 只存 id，不存标题/图标 —— 插件更名或下架时首页不会显示脏数据。
//  - 勾选和排序放同一页：上半区是已选（可拖动），下半区是可选池。
//    分成两页会让「选完还得再进一个页面排序」，多一次跳转不值得。
library;

import 'package:flutter/material.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';
import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/home/data/home_quick_action_prefs.dart';

class QuickActionPickerPage extends StatefulWidget {
  const QuickActionPickerPage({super.key, this.prefs});

  /// 允许注入，便于测试；生产走默认实现。
  final HomeQuickActionPrefs? prefs;

  @override
  State<QuickActionPickerPage> createState() => _QuickActionPickerPageState();
}

class _QuickActionPickerPageState extends State<QuickActionPickerPage> {
  late final HomeQuickActionPrefs _prefs =
      widget.prefs ?? HomeQuickActionPrefs();

  List<String> _selected = <String>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = await _prefs.readSelectedIds();
    if (!mounted) return;
    setState(() {
      _selected = ids;
      _loading = false;
    });
  }

  Future<void> _persist(List<String> next) async {
    // 先更新 UI 再落盘：勾选要即时响应，存储是毫秒级的本地写入。
    setState(() => _selected = next);
    await _prefs.saveSelectedIds(next);
  }

  Future<void> _toggle(String id) async {
    if (_selected.contains(id)) {
      await _persist(_selected.where((e) => e != id).toList());
      return;
    }
    if (_selected.length >= HomeQuickActionPrefs.maxSlots) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '最多只能放 ${HomeQuickActionPrefs.maxSlots} 个快捷入口，'
            '先移除一个再添加',
          ),
        ),
      );
      return;
    }
    await _persist(<String>[..._selected, id]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        title: const Text('自选快捷入口'),
        backgroundColor: AppTokens.surface,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeValueListenableBuilder<List<HomePlugin>>(
              valueListenable: HomePluginHost.instance.listenable,
              builder: (context, plugins, child) {
                // 可选池：所有已启用的插件（内置 + 用户安装）。
                final available = plugins.where((p) => p.enabled).toList();
                final byId = <String, HomePlugin>{
                  for (final p in available) p.id: p,
                };

                // 已选里可能有「插件被卸载/停用」的残留 id，这里过滤掉再显示，
                // 但不静默改存储 —— 用户重新装回插件后顺序还能恢复。
                final selectedPlugins = _selected
                    .map((id) => byId[id])
                    .whereType<HomePlugin>()
                    .toList();

                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.shellPageGutter,
                    12,
                    AppTokens.shellPageGutter,
                    32,
                  ),
                  children: <Widget>[
                    _sectionTitle(
                      '已放到首页（${selectedPlugins.length}/'
                      '${HomeQuickActionPrefs.maxSlots}）',
                      subtitle: '长按拖动可调整顺序',
                    ),
                    if (selectedPlugins.isEmpty)
                      _hintCard('还没有选任何入口，从下面添加')
                    else
                      _selectedList(selectedPlugins),
                    const SizedBox(height: 18),
                    _sectionTitle('可添加的插件'),
                    ...available
                        .where((p) => !_selected.contains(p.id))
                        .map(_availableRow),
                    if (available.every((p) => _selected.contains(p.id)))
                      _hintCard('所有插件都已添加'),
                  ],
                );
              },
            ),
    );
  }

  Widget _selectedList(List<HomePlugin> selectedPlugins) {
    // 同 _availableRow：容器用 Material 提供背景，否则内部 ListTile
    // 的水波纹会被带 color 的 DecoratedBox 遮住并触发断言。
    return Material(
      color: AppTokens.surface,
      // 注意：Material 不允许同时传 shape 和 borderRadius（会断言失败），
      // shape 里的 RoundedRectangleBorder 已经带圆角了。
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTokens.divider),
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      ),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: selectedPlugins.length,
        onReorder: (oldIndex, newIndex) async {
          // ReorderableListView 的 newIndex 语义是「插入点」，
          // 往后拖时要减 1 才是最终下标，否则会差一位。
          var target = newIndex;
          if (target > oldIndex) target -= 1;
          final next = List<String>.from(_selected);
          final moved = next.removeAt(oldIndex);
          next.insert(target, moved);
          await _persist(next);
        },
        itemBuilder: (context, index) {
          final plugin = selectedPlugins[index];
          return ReorderableDragStartListener(
            key: ValueKey<String>(plugin.id),
            index: index,
            child: ListTile(
              leading: _iconBadge(plugin),
              title: Text(
                plugin.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.textPrimary,
                ),
              ),
              subtitle: plugin.subtitle.isEmpty
                  ? null
                  : Text(
                      plugin.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTokens.textTertiary,
                      ),
                    ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.drag_handle_rounded,
                    color: AppTokens.textTertiary,
                    size: 20,
                  ),
                  IconButton(
                    tooltip: '移出首页',
                    icon: const Icon(
                      Icons.remove_circle_outline_rounded,
                      color: AppTokens.danger,
                      size: 20,
                    ),
                    onPressed: () => _toggle(plugin.id),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _availableRow(HomePlugin plugin) {
    // 用 Material 而不是 Container+decoration 包 ListTile：
    // ListTile 把背景和水波纹画在最近的 Material 祖先上，外面套一层
    // 带 color 的 DecoratedBox 会把这些效果盖掉，Flutter 会直接断言报错。
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTokens.surface,
        // 同上：shape 与 borderRadius 互斥，只留 shape。
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppTokens.divider),
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
        child: ListTile(
          leading: _iconBadge(plugin),
          title: Text(
            plugin.title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTokens.textPrimary,
            ),
          ),
          subtitle: plugin.subtitle.isEmpty
              ? null
              : Text(
                  plugin.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTokens.textTertiary,
                  ),
                ),
          trailing: IconButton(
            tooltip: '加到首页',
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: AppTokens.primaryBlue,
            ),
            onPressed: () => _toggle(plugin.id),
          ),
          onTap: () => _toggle(plugin.id),
        ),
      ),
    );
  }

  Widget _iconBadge(HomePlugin plugin) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: plugin.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusChip),
      ),
      child: Icon(plugin.icon, color: plugin.color, size: 18),
    );
  }

  Widget _sectionTitle(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppTokens.textPrimary,
            ),
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppTokens.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hintCard(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: AppTokens.divider),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: AppTokens.textTertiary),
      ),
    );
  }
}

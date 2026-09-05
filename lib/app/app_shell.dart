import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_drawer.dart';
import '../design_system/app_tokens.dart';
import '../design_system/widgets/app_bottom_sheet.dart';
import '../globals.dart';
import '../features/content/presentation/warehouse_tab.dart';
import '../features/extensions/presentation/plugin_tab.dart';
import '../features/home/presentation/home_page.dart';
import '../features/tools/presentation/tool_page.dart';
import '../novel/pages/source_manager/book_source_bootstrap.dart';
import '../novel/pages/source_manager/book_source_manager.dart';
import '../novel/pages/source_manager/book_source_manager_page.dart';
import '../video_module.dart';
import '../features/quiz_plugin/data/quiz_cloud_auto_sync.dart';
import '../features/policy/plugin_policy.dart';
import '../features/extensions/market/data/plugin_market_local_sync.dart';
import '../features/cloud_sync/data/book_source_cloud_sync.dart';
import '../features/cloud_sync/domain/announcement_center.dart';
import '../features/cloud_sync/presentation/announcement_popup.dart';

/// 桌面端断点 — ≥800px 切换 NavigationRail
const double _desktopBreakpoint = 800;

class MainAppShell extends StatefulWidget {
  const MainAppShell({super.key, required this.novelBootstrap});

  final BookSourceBootstrapResult novelBootstrap;

  @override
  State<MainAppShell> createState() => _MainAppShellState();
}

class _MainAppShellState extends State<MainAppShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  late final PageController _pageController;
  bool _novelBootstrapPromptShown = false;

  late final List<_TabItem> _tabs = [
    _TabItem(
      title: '首页',
      icon: Icons.home_rounded,
      widget: HomePage(onSwitchTab: _onItemTapped),
    ),
    const _TabItem(
      title: '工具',
      icon: Icons.grid_view_rounded,
      widget: ToolPage(),
    ),
    const _TabItem(
      title: '内容',
      icon: Icons.collections_bookmark_rounded,
      widget: WarehouseTab(),
    ),
    const _TabItem(
      title: '扩展',
      icon: Icons.extension_rounded,
      widget: PluginTab(),
    ),
  ];

  /// 快捷键绑定
  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    return {
      const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
          _onItemTapped(0),
      const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
          _onItemTapped(1),
      const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
          _onItemTapped(2),
      const SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
          _onItemTapped(3),
    };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: _currentIndex);
    QuizCloudAutoSync.instance.scheduleStartup();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePromptNovelSourceConfig();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final manager = context.read<BookSourceManager>();
      await manager.load();
      // 本地书源就绪后再机会性同步云端（距上次不足 6h 直接跳过，失败静默）。
      if (!mounted) return;
      await BookSourceCloudSyncService().syncIfStale(
        prefs: await SharedPreferences.getInstance(),
        manager: manager,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<HistoryController>().loadHistory();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<FavoritesController>().load();
    });
    // 公告：首帧后再拉，不阻塞冷启动。进入 App 必刷新，失败静默。
    // 拉完若有未读的 warning 级公告，弹一次窗 —— 更新验签这类故障必须能
    // 主动触达用户，不能指望他自己翻到「抽屉 → 账号 → 个人中心」。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final center = context.read<AnnouncementCenter>();
      await center.bootstrap();
      if (!mounted) return;
      await _maybeShowAnnouncementPopup(center);
    });
  }

  Future<void> _maybeShowAnnouncementPopup(AnnouncementCenter center) async {
    final popup = center.takePopup();
    if (popup == null || !mounted) return;
    await showAnnouncementPopup(
      context: context,
      entry: popup,
      onAcknowledged: () => center.acknowledge(popup.id),
    );
  }

  Future<void> _refreshAnnouncementsOnResume() async {
    if (!mounted) return;
    final center = context.read<AnnouncementCenter>();
    await center.refresh();
    if (!mounted) return;
    await _maybeShowAnnouncementPopup(center);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      QuizCloudAutoSync.instance.onAppResumed();
      _refreshAnnouncementsOnResume();
      // 回前台刷新插件远程策略（节流在 Store 内）
      PluginPolicyStore.instance.refresh();
      // 回前台同步市场插件下架状态并强制禁用
      PluginMarketLocalSync().syncInstalledStatuses();
    }
  }

  void _onItemTapped(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);

    // Top-level tab changes can jump multiple heavy sections (首页 → 扩展).
    // Animating a PageView across every intermediate page forces Tool/Content/
    // Plugin pages to build during the transition, which causes visible jank.
    // Use an instant page switch; each tab still preserves its state via
    // AutomaticKeepAliveClientMixin.
    if (_pageController.hasClients) {
      _pageController.jumpToPage(index);
    }
  }

  Future<void> _maybePromptNovelSourceConfig() async {
    if (_novelBootstrapPromptShown) return;
    _novelBootstrapPromptShown = true;

    if (widget.novelBootstrap.configured) return;
    if (!mounted) return;

    final message = widget.novelBootstrap.message.isNotEmpty
        ? widget.novelBootstrap.message
        : '当前还没有可用的规则书源，部分小说功能将不可用，请先导入并启用一个书源。';

    final shouldOpenManager = await showAppModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => AppBottomSheetFrame(
        title: '小说书源未配置',
        subtitle: '导入并启用一个书源后，小说搜索、详情和阅读功能才会完整可用。',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTokens.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                border: Border.all(
                  color: AppTokens.warning.withValues(alpha: 0.20),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: AppTokens.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: AppTokens.textPrimary,
                        height: 1.45,
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
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: const Text('稍后再说'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('去配置'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (shouldOpenManager != true || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookSourceManagerPage(
          startupMessage: widget.novelBootstrap.message,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: _shortcuts,
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
            if (isDesktop) {
              return _buildDesktopLayout();
            }
            return _buildMobileLayout();
          },
        ),
      ),
    );
  }

  /// 桌面端：NavigationRail + 内容区
  Widget _buildDesktopLayout() {
    return Scaffold(
      key: appScaffoldKey,
      drawer: const AppDrawer(),
      drawerScrimColor: Colors.black.withValues(alpha: 0.30),
      body: Row(
        children: [
          _AppNavigationRail(
            tabs: _tabs,
            currentIndex: _currentIndex,
            onTap: _onItemTapped,
            onOpenDrawer: () => appScaffoldKey.currentState?.openDrawer(),
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                if (_currentIndex != index) {
                  setState(() => _currentIndex = index);
                }
              },
              children: _tabs.map((tab) => tab.widget).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 移动端：PageView + 底部标签栏（保留原有 UI）
  Widget _buildMobileLayout() {
    return Scaffold(
      key: appScaffoldKey,
      drawer: const AppDrawer(),
      drawerScrimColor: Colors.black.withValues(alpha: 0.30),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (index) {
          if (_currentIndex != index) {
            setState(() => _currentIndex = index);
          }
        },
        children: _tabs.map((tab) => tab.widget).toList(),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: List.generate(_tabs.length, (index) {
              final tab = _tabs[index];
              final selected = _currentIndex == index;
              return Expanded(
                child: _ShellNavItem(
                  title: tab.title,
                  icon: tab.icon,
                  selected: selected,
                  onTap: () => _onItemTapped(index),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// 选项卡数据模型
class _TabItem {
  final String title;
  final IconData icon;
  final Widget widget;

  const _TabItem({
    required this.title,
    required this.icon,
    required this.widget,
  });
}

/// 桌面端 NavigationRail — 风格与移动端底部导航完全一致
class _AppNavigationRail extends StatelessWidget {
  final List<_TabItem> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onOpenDrawer;

  const _AppNavigationRail({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
    required this.onOpenDrawer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      margin: const EdgeInsets.fromLTRB(10, 10, 0, 10),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // 菜单按钮
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: IconButton(
              icon: const Icon(Icons.menu_rounded, size: 20),
              tooltip: '打开菜单',
              onPressed: onOpenDrawer,
            ),
          ),
          const SizedBox(height: 2),
          // Logo
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF06B6D4)],
              ),
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            ),
            child: const Center(
              child: Text(
                'G',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 导航项
          ...List.generate(tabs.length, (index) {
            final tab = tabs[index];
            return _DesktopNavItem(
              title: tab.title,
              icon: tab.icon,
              selected: currentIndex == index,
              onTap: () => onTap(index),
            );
          }),
          const Spacer(),
          // 设置按钮
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: IconButton(
              icon: const Icon(Icons.settings_outlined, size: 20),
              tooltip: '设置',
              onPressed: () => Navigator.pushNamed(context, '/account'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 桌面侧边栏导航项 — 与移动端 [_ShellNavItem] 样式完全一致
class _DesktopNavItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _DesktopNavItem({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: selected ? 40 : 36,
                height: selected ? 40 : 36,
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(
                          colors: [Color(0xFF2563EB), Color(0xFF06B6D4)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: selected ? null : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: Icon(
                  icon,
                  size: selected ? 20 : 18,
                  color: selected ? Colors.white : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF64748B),
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 移动端底部导航项
class _ShellNavItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ShellNavItem({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: selected ? 28 : 26,
              height: selected ? 28 : 26,
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF06B6D4)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: selected ? null : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              ),
              child: Icon(
                icon,
                size: selected ? 17 : 16,
                color: selected ? Colors.white : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? selectedColor : const Color(0xFF64748B),
                fontSize: 11,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

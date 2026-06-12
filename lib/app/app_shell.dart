import 'package:flutter/material.dart';

import '../app_drawer.dart';
import '../design_system/app_tokens.dart';
import '../globals.dart';
import '../features/content/presentation/warehouse_tab.dart';
import '../features/extensions/presentation/plugin_tab.dart';
import '../features/home/presentation/home_page.dart';
import '../features/tools/presentation/tool_page.dart';
import '../novel/pages/source_manager/book_source_bootstrap.dart';
import '../novel/pages/source_manager/book_source_manager_page.dart';

class MainAppShell extends StatefulWidget {
  const MainAppShell({super.key, required this.novelBootstrap});

  final BookSourceBootstrapResult novelBootstrap;

  @override
  State<MainAppShell> createState() => _MainAppShellState();
}

class _MainAppShellState extends State<MainAppShell> {
  int _currentIndex = 0;
  late final PageController _pageController;
  bool _novelBootstrapPromptShown = false;

  late final List<Map<String, dynamic>> _tabs = [
    {
      'title': '首页',
      'icon': Icons.home_rounded,
      'widget': HomePage(onSwitchTab: _onItemTapped),
    },
    {
      'title': '工具',
      'icon': Icons.grid_view_rounded,
      'widget': const ToolPage(),
    },
    {
      'title': '内容',
      'icon': Icons.collections_bookmark_rounded,
      'widget': const WarehouseTab(),
    },
    {
      'title': '扩展',
      'icon': Icons.extension_rounded,
      'widget': const PluginTab(),
    },
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePromptNovelSourceConfig();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.decelerate,
    );
  }

  Future<void> _maybePromptNovelSourceConfig() async {
    if (_novelBootstrapPromptShown) return;
    _novelBootstrapPromptShown = true;

    if (widget.novelBootstrap.configured) return;
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('小说书源未配置'),
          content: Text(
            widget.novelBootstrap.message.isNotEmpty
                ? widget.novelBootstrap.message
                : '当前还没有可用的规则书源，部分小说功能将不可用，请先导入并启用一个书源。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('稍后再说'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BookSourceManagerPage(
                      startupMessage: widget.novelBootstrap.message,
                    ),
                  ),
                );
              },
              child: const Text('去配置'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
        children: _tabs.map((tab) => tab['widget'] as Widget).toList(),
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
                  title: tab['title'] as String,
                  icon: tab['icon'] as IconData,
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

class _ShellNavItem extends StatelessWidget {
  const _ShellNavItem({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

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
              width: selected ? 25 : 23,
              height: selected ? 25 : 23,
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
                size: selected ? 15 : 14,
                color: selected ? Colors.white : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 0),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? selectedColor : const Color(0xFF64748B),
                fontSize: 9.5,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

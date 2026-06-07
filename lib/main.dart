import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_drawer.dart';
import 'design_system/app_theme.dart';
import 'globals.dart';
import 'home_page.dart';
import 'plugin_tab.dart';
import 'tool_page.dart';
import 'update/update_bootstrap_page.dart';
import 'video_module.dart';
import 'warehouse_tab.dart';

import 'pages/debug_log_page.dart';
import 'utils/app_logger.dart';
import 'utils/http_overrides.dart';

// 小说模块相关
import 'novel/pages/source_manager/book_source_bootstrap.dart';
import 'novel/pages/source_manager/book_source_manager.dart';
import 'novel/pages/source_manager/book_source_manager_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 证书忽略：仅调试环境启用，避免 release 全局接受不安全 HTTPS 证书。
  if (kDebugMode) {
    enableInsecureCertificateOverrides();
  }

  await Hive.initFlutter();

  // 初始化日志系统
  try {
    await AppLogger.instance.init();
  } catch (e) {
    debugPrint('AppLogger init failed: $e');
  }

  // Flutter 框架错误捕获
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);

    AppLogger.instance.log(
      'FlutterError: ${details.exceptionAsString()}',
      tag: 'FLUTTER',
    );

    if (details.stack != null) {
      AppLogger.instance.log(details.stack.toString(), tag: 'FLUTTER');
    }
  };

  // Dart 运行时错误捕获
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.instance.logError(error, stack, 'DART');
    return true;
  };

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // =========================
  // 小说模块：启动自动加载规则书源
  // =========================
  final prefs = await SharedPreferences.getInstance();
  final novelBootstrap = await BookSourceBootstrap.loadAndConfigure(prefs);

  // =========================
  // 视频源配置（保留你原来的逻辑）
  // =========================
  VideoModule.configureLicensedCatalogSource(
    catalogName: 'OuonnkiTV',
    catalogUrls: const [
      'https://proxy.shuabu.eu.org?format=0&source=jin18',
      'https://proxy.shuabu.eu.org?format=1&source=jin18',
    ],
  );

  runZonedGuarded(
    () {
      runApp(
        MultiProvider(
          providers: [
            // 小说书源管理器
            ChangeNotifierProvider<BookSourceManager>(
              create: (_) => BookSourceManager(prefs)..load(),
            ),

            // 视频相关
            ChangeNotifierProvider<VideoController>(
              create: (_) => VideoController(),
            ),
            ChangeNotifierProvider<HistoryController>(
              create: (_) {
                final controller = HistoryController();
                controller.loadHistory();
                return controller;
              },
            ),
          ],
          child: MyApp(novelBootstrap: novelBootstrap),
        ),
      );
    },
    (error, stack) {
      AppLogger.instance.logError(error, stack, 'ZONE');
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.novelBootstrap});

  final BookSourceBootstrapResult novelBootstrap;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geek工具箱',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [appRouteObserver],
      routes: {
        '/debug-log': (_) => const DebugLogPage(),
        '/book-source-manager': (_) => BookSourceManagerPage(
          startupMessage: novelBootstrap.configured
              ? ''
              : novelBootstrap.message,
        ),
      },
      theme: AppTheme.light(),
      home: UpdateBootstrapPage(
        nextPage: MainAppShell(novelBootstrap: novelBootstrap),
        appId: 'box',
        checkUrl: 'https://box.hpa888.top/api/v1/app-updates/check',
        platform: 'android',
        channel: 'release',
        allowProceedOnCheckFailure: true,
      ),
    );
  }
}

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
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(24),
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? selectedColor.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: selected ? 31 : 28,
              height: selected ? 31 : 28,
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF06B6D4)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: selected ? null : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: selected ? 18 : 17,
                color: selected ? Colors.white : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 3),
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

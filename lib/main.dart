import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_drawer.dart';
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

  // 证书忽略：IO 端生效，Web 端自动 no-op
  enableInsecureCertificateOverrides();

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

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

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
          child: MyApp(
            novelBootstrap: novelBootstrap,
          ),
        ),
      );
    },
    (error, stack) {
      AppLogger.instance.logError(error, stack, 'ZONE');
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.novelBootstrap,
  });

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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.light,
        ),
        cardTheme: const CardThemeData(
          elevation: 0.5,
          margin: EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      ),
      home: UpdateBootstrapPage(
        nextPage: MainAppShell(
          novelBootstrap: novelBootstrap,
        ),
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
  const MainAppShell({
    super.key,
    required this.novelBootstrap,
  });

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
      'widget': const HomePage(),
    },
    {
      'title': '工具',
      'icon': Icons.grid_view_rounded,
      'widget': const ToolPage(),
    },
    {
      'title': '仓库',
      'icon': Icons.inventory_2_rounded,
      'widget': const WarehouseTab(),
    },
    {
      'title': '插件',
      'icon': Icons.extension_rounded,
      'widget': const PluginTab(),
    },
    {
      'title': '视频',
      'icon': Icons.smart_display_rounded,
      'widget': const VideoListPage(),
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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onItemTapped,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Colors.grey.shade500,
          backgroundColor: Colors.white,
          showUnselectedLabels: true,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          items: _tabs.map((tab) {
            return BottomNavigationBarItem(
              icon: Icon(tab['icon'] as IconData),
              label: tab['title'] as String,
              activeIcon: Icon(
                tab['icon'] as IconData,
                color: Theme.of(context).colorScheme.primary,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
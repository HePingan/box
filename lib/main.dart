import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_drawer.dart';
import 'globals.dart';
import 'home_page.dart';
import 'novel/novel_module.dart';
import 'plugin_tab.dart';
import 'tool_page.dart';
import 'video_module.dart';
import 'warehouse_tab.dart';
import 'package:flutter/foundation.dart';
import 'update/update_bootstrap_page.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  NovelModule.configureQimao(
    baseUrl: 'http://api.lemiyigou.com',
    headers: const {
      'User-Agent': 'okhttp/4.9.2',
      'client-device': '2d37f6b5b6b2605373092c3dc65a3b39',
      'client-brand': 'Redmi',
      'client-version': '2.3.0',
      'client-name': 'app.maoyankanshu.novel',
      'client-source': 'android',
      'Authorization':
          'bearereyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwOlwvXC9hcGkuanhndHp4Yy5jb21cL2F1dGhcL3RoaXJkIiwiaWF0IjoxNjgzODkxNjUyLCJleHAiOjE3NzcyMDM2NTIsIm5iZiI6MTY4Mzg5MTY1MiwianRpIjoiR2JxWmI4bGZkbTVLYzBIViIsInN1YiI6Njg3ODYyLCJwcnYiOiJhMWNiMDM3MTgwMjk2YzZhMTkzOGVmMzBiNDM3OTQ2NzJkZDAxNmM1In0.mMxaC2SVyZKyjC6rdUqFVv5d9w_X36o0AdKD7szvE_Q',
    },
  );

  // 4. 视频模块配置 (注入你指定的授权 JSON 接口)
  VideoModule.configureLicensedCatalogSource(
    catalogName: 'OuonnkiTV',
    catalogUrls: const [
      // 优先使用加速链接，防止国内直连 GitHub raw 失败
      'https://gh-proxy.org/https://raw.githubusercontent.com/ZhuBaiwan-oOZZXX/OuonnkiTV-Source/main/tv_source/OuonnkiTV/full-noadult.json',
      'https://ghfast.top/https://raw.githubusercontent.com/ZhuBaiwan-oOZZXX/OuonnkiTV-Source/main/tv_source/OuonnkiTV/full-noadult.json',
      // 原链接作为最后兜底
      'https://raw.githubusercontent.com/ZhuBaiwan-oOZZXX/OuonnkiTV-Source/main/tv_source/OuonnkiTV/full-noadult.json',
    ],
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geek工具箱',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [appRouteObserver],
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
  nextPage: const MainAppShell(),
  appId: 'box',
  checkUrl: 'http://47.109.97.1:8000/api/v1/app-updates/check',
  platform: 'android',
  channel: 'release',
  allowProceedOnCheckFailure: true,
),
    );
  }
}

class MainAppShell extends StatefulWidget {
  const MainAppShell({super.key});

  @override
  State<MainAppShell> createState() => _MainAppShellState();
}

class _MainAppShellState extends State<MainAppShell> {
  int _currentIndex = 0;
  late final PageController _pageController;

  final List<Map<String, dynamic>> _tabs = [
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
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
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

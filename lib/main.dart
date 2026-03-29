import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 模块与组件导入
import 'app_drawer.dart';
import 'globals.dart';
import 'home_page.dart';
import 'novel/novel_module.dart';
import 'tool_page.dart';
import 'video_module.dart';

Future<void> main() async {
  // 1. 确保 Flutter 引擎初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 2. 设置系统 UI 样式 (沉浸式状态栏)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // 3. 小说模块配置 (七猫源)
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

  // 4. 视频模块配置 (使用最新的 TVBox 聚合源)
  VideoModule.configurePublicVideoSource();

  // 5. 启动应用
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
        // 基于蓝色种子生成全套色彩方案
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.light,
        ),
        // --- 修复位置: 使用 CardThemeData 而不是 CardTheme ---
        cardTheme: const CardThemeData(
          elevation: 0.5,
          margin: EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        // ---------------------------------------------
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      ),
      home: const MainAppShell(),
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

  // 底部导航栏配置
  final List<Map<String, dynamic>> _tabs = [
    {'title': '首页', 'icon': Icons.home_rounded, 'widget': const HomePage()},
    {'title': '工具', 'icon': Icons.grid_view_rounded, 'widget': const ToolPage()},
    {'title': '仓库', 'icon': Icons.inventory_2_rounded, 'widget': const Center(child: Text('核心仓库正在筹备中...'))},
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
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          items: _tabs.map((tab) {
            return BottomNavigationBarItem(
              icon: Icon(tab['icon']),
              label: tab['title'],
              activeIcon: Icon(tab['icon'], color: Theme.of(context).colorScheme.primary),
            );
          }).toList(),
        ),
      ),
    );
  }
}
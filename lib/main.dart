import 'package:flutter/material.dart';

import 'app_drawer.dart';
import 'globals.dart';
import 'home_page.dart';
import 'tool_page.dart';
import 'novel/novel_module.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 👉 关键修复：把原本 JSON 里的 header 全部完整搬过来 
  NovelModule.configureQimao(
    baseUrl: 'http://api.lemiyigou.com',
    headers: const {
      'User-Agent': 'okhttp/4.9.2',
      'client-device': '2d37f6b5b6b2605373092c3dc65a3b39',
      'client-brand': 'Redmi',
      'client-version': '2.3.0',
      'client-name': 'app.maoyankanshu.novel',
      'client-source': 'android',
      'Authorization': 'bearereyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwOlwvXC9hcGkuanhndHp4Yy5jb21cL2F1dGhcL3RoaXJkIiwiaWF0IjoxNjgzODkxNjUyLCJleHAiOjE3NzcyMDM2NTIsIm5iZiI6MTY4Mzg5MTY1MiwianRpIjoiR2JxWmI4bGZkbTVLYzBIViIsInN1YiI6Njg3ODYyLCJwcnYiOiJhMWNiMDM3MTgwMjk2YzZhMTkzOGVmMzBiNDM3OTQ2NzJkZDAxNmM1In0.mMxaC2SVyZKyjC6rdUqFVv5d9w_X36o0AdKD7szvE_Q',
    },
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geek工具箱合集',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
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
  late PageController _pageController;

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
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
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
          setState(() => _currentIndex = index);
        },
        children: const [
          HomePage(),
          ToolPage(),
          Center(child: Text("仓库功能开发中...")),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.blue[700],
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: '首页'),
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: '工具'),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            label: '仓库',
          ),
        ],
      ),
    );
  }
} 
// lib/daily_news_page.dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class DailyNewsPage extends StatefulWidget {
  const DailyNewsPage({super.key});

  @override
  State<DailyNewsPage> createState() => _DailyNewsPageState();
}

class _DailyNewsPageState extends State<DailyNewsPage> {
  // 定义网页控制器
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    // 初始化网页控制器，设置允许运行JS，并加载你提供的网址
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://actcpc.heytapimage.com/oh5/3/1/index.html#/'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // 自定义顶部标题栏（按照图2复刻）
      appBar: AppBar(
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0, // 页面滚动时不要变色
        elevation: 0,
        // 左侧返回按钮
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        // 标题
        title: const Text(
          '视界日报', 
          style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)
        ),
        centerTitle: false,
        // 右侧的刷新和更多按钮
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: () {
              _controller.reload(); // 点击刷新网页
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black87),
            onPressed: () {
              // 更多功能留空
            },
          ),
        ],
      ),
      
      // 主体部分显示网页视图
      body: WebViewWidget(controller: _controller),
    );
  }
}
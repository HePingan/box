// lib/tool_web_page.dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ToolWebPage extends StatefulWidget {
  final String title; // 工具的名字 (比如：在线PS)
  final String url;   // 工具的网址 (比如：https://www.photopea.com/)

  const ToolWebPage({super.key, required this.title, required this.url});

  @override
  State<ToolWebPage> createState() => _ToolWebPageState();
}

class _ToolWebPageState extends State<ToolWebPage> {
  late final WebViewController _controller;
  bool _isLoading = true; // 加载状态指示

  @override
  void initState() {
    super.initState();
    // 初始化网页控制器，打开JS权限，以此保证 Photopea 这类复杂的网页能正常运行
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            // 网页加载完成了，关掉转圈圈
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url)); // 加载你传过来的网址
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          // 添加一个刷新按钮，如果工具卡住了可以点击重载
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _controller.reload();
            },
          ),
        ],
      ),
      // Stack 将网页和加载动画叠在一起
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Colors.blue), // 蓝色的加载小圆圈
            ),
        ],
      ),
    );
  }
}
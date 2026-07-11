// lib/tool_web_page.dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'design_system/widgets/app_back_button.dart';

class ToolWebPage extends StatefulWidget {
  final String title; // 工具的名字 (比如：在线PS)
  final String url; // 工具的网址 (比如：https://www.photopea.com/)

  const ToolWebPage({super.key, required this.title, required this.url});

  @override
  State<ToolWebPage> createState() => _ToolWebPageState();
}

class _ToolWebPageState extends State<ToolWebPage> {
  late final WebViewController _controller;
  late final Uri? _initialUri;
  bool _isLoading = true; // 加载状态指示
  bool _hasValidInitialUrl = true;

  @override
  void initState() {
    super.initState();
    _initialUri = Uri.tryParse(widget.url.trim());
    final initialUri = _initialUri;
    _hasValidInitialUrl = initialUri != null && _isAllowedUri(initialUri);

    // 初始化网页控制器，打开JS权限，以此保证 Photopea 这类复杂的网页能正常运行
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null || !_isAllowedUri(uri)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (String url) {
            // 网页加载完成了，关掉转圈圈
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
          onWebResourceError: (_) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
        ),
      );

    if (_hasValidInitialUrl) {
      _controller.loadRequest(_initialUri!);
    } else {
      _isLoading = false;
    }
  }

  bool _isAllowedUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') return false;

    final initialHost = _initialUri?.host.toLowerCase();
    final host = uri.host.toLowerCase();
    return initialHost != null &&
        (host == initialHost || host.endsWith('.$initialHost'));
  }

  @override
  void dispose() {
    _controller.clearCache();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: AppBackButton(
          onPressed: () => Navigator.pop(context),
          label: widget.title,
        ),
        actions: [
          // 添加一个刷新按钮，如果工具卡住了可以点击重载
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _hasValidInitialUrl
                ? () {
                    setState(() => _isLoading = true);
                    _controller.reload();
                  }
                : null,
          ),
        ],
      ),
      // Stack 将网页和加载动画叠在一起
      body: Stack(
        children: [
          if (_hasValidInitialUrl)
            WebViewWidget(controller: _controller)
          else
            const Center(child: Text('无效或不受信任的网页地址')),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Colors.blue), // 蓝色的加载小圆圈
            ),
        ],
      ),
    );
  }
}

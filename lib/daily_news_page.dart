// lib/daily_news_page.dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'daily_news_url_policy.dart';
import 'design_system/widgets/app_back_button.dart';

class DailyNewsPage extends StatefulWidget {
  const DailyNewsPage({super.key, this.initialUrl});

  /// 具体新闻的 URL，为空时加载默认门户页
  final String? initialUrl;

  @override
  State<DailyNewsPage> createState() => _DailyNewsPageState();
}

class _DailyNewsPageState extends State<DailyNewsPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null || !DailyNewsUrlPolicy.isAllowed(uri)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(_initialUri());
  }

  Uri _initialUri() => DailyNewsUrlPolicy.resolve(widget.initialUrl);

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
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: AppBackButton(
          onPressed: () => Navigator.pop(context),
          label: widget.initialUrl != null ? '热点详情' : '视界日报',
        ),
        title: Text(
          widget.initialUrl != null ? '热点详情' : '视界日报',
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}

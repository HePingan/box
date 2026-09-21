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
        // label 故意留空：当前页名交给下面的 title。
        // 这里曾经也传了同一个字符串，AppBar.leading 宽度固定（内容区仅约 34dp）
        // 装不下「图标+4 汉字」，溢出后与紧邻的 title 水平重叠 —— 用户截图里
        // 「热点」和「热点详情」糊在一起就是这个。
        // label 的语义是「返回到哪儿」（目的地），不是「当前页叫什么」。
        leading: AppBackButton(
          onPressed: () => Navigator.pop(context),
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

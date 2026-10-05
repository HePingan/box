// lib/daily_news_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'design_system/app_tokens.dart';

import 'daily_news_url_policy.dart';
import 'design_system/widgets/app_back_button.dart';

/// 站内 WebView 页：今日热闻、AI 热点的详情，以及插件目录里的门户入口。
///
/// 三件事按 [DailyNewsUrlPolicy] 的真话来做：
/// ① 能站内开的原样开；② 站外的（x.com / arxiv）**如实说打不开**并给可复制的原地址，
/// 不再静默换成视界日报门户页；③ 标题按真正加载的主机取名，
/// 不写死一个来源名 —— 写死过一次：数据源从视界日报换成知乎日报后，
/// 用户在知乎日报的文章页上看到标题写着「视界日报」。
class DailyNewsPage extends StatefulWidget {
  const DailyNewsPage({super.key, this.initialUrl, this.title});

  /// 要打开的地址。为空时加载默认门户页（插件入口那种「看门户」的用法）。
  final String? initialUrl;

  /// AppBar 标题。不传就按实际加载的主机推（AI 热点 / 知乎日报 / 视界日报）。
  final String? title;

  @override
  State<DailyNewsPage> createState() => _DailyNewsPageState();
}

class _DailyNewsPageState extends State<DailyNewsPage> {
  late final DailyNewsTarget _target;

  /// 站外地址不给 WebView：开一个空白页只会让人觉得「内容不对」，
  /// 页面改成如实说明 + 可复制原文地址。
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    _target = DailyNewsUrlPolicy.decide(widget.initialUrl);
    if (_target.isBlocked) return;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(onNavigationRequest: _onNavigationRequest),
      )
      ..loadRequest(_target.uri);
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null || !DailyNewsUrlPolicy.isAllowed(uri)) {
      // 站内页面里点到站外链接：以前是静默 prevent —— 用户点了没有任何反应，
      // 只会报成「页面坏了」。现在给一句明确的话 + 可复制的地址。
      _tellBlockedLink(request.url);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  void _tellBlockedLink(String url) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: const Text('这是站外链接，只能在浏览器里打开'),
        action: SnackBarAction(
          label: '复制链接',
          onPressed: () => _copy(url),
        ),
      ),
    );
  }

  static Future<void> _copy(String url) {
    return Clipboard.setData(ClipboardData(text: url));
  }

  /// 按真正要加载的主机取名。
  String get _pageTitle {
    final explicit = widget.title?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return _titleForHost(_target.uri.host);
  }

  static String _titleForHost(String host) {
    final h = host.toLowerCase();
    if (h.endsWith('aihot.news') || h.endsWith('aihot.virxact.com')) {
      return 'AI 热点';
    }
    if (h.endsWith('zhihu.com')) return '知乎日报';
    if (h.endsWith('heytapimage.com')) return '视界日报';
    return '详情';
  }

  @override
  void dispose() {
    _controller?.clearCache();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: AppTokens.surface,
      appBar: AppBar(
        backgroundColor: AppTokens.surface,
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
          _pageTitle,
          style: TextStyle(
            color: AppTokens.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        actions: controller == null
            ? null
            : <Widget>[
                IconButton(
                  icon: Icon(Icons.refresh, color: AppTokens.textPrimary),
                  onPressed: () => controller.reload(),
                ),
              ],
      ),
      body: controller == null
          ? _BlockedLinkBody(url: _target.blockedUrl ?? '')
          : WebViewWidget(controller: controller),
    );
  }
}

/// 站外地址的说明页：告诉用户为什么打不开，并把地址交给他复制。
class _BlockedLinkBody extends StatelessWidget {
  const _BlockedLinkBody({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.link_off_rounded, size: 40, color: AppTokens.textTertiary),
          const SizedBox(height: 14),
          Text(
            '这条内容要在浏览器里打开',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '它指向站外站点（AI 热点的原文常在 X、arXiv 这类地方），App 内的阅读器打不开。'
            '可以把下面的地址复制到浏览器。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.5, color: AppTokens.textSecondary),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTokens.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              url,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppTokens.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              await _DailyNewsPageState._copy(url);
              if (!context.mounted) return;
              ScaffoldMessenger.maybeOf(
                context,
              )?.showSnackBar(const SnackBar(content: Text('链接已复制')));
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('复制链接'),
          ),
        ],
      ),
    );
  }
}

// 服务器运维插件：「终端」页签 —— webview 打开运维终端。
//
// 关键一条：终端端点挂了 Basic 认证，**认证必须由 onHttpAuthRequest 应答**，
// 否则页面会一直停在 401（webview 自己不会弹账号框）。用户名/口令来自
// ServerOpsSettings（构建注入优先，用户填过以用户的为准）。
//
// 关于 API：本仓库锁定的 webview_flutter 里 `NavigationDelegate.onHttpAuthRequest`
// 的回调形参是 `HttpAuthRequest`，应答方式是 `request.onProceed(WebViewCredential(...))`
// / `request.onCancel()`（老版本的 `HttpAuthResponse(proceed: ...)` 已经不在这个
// 版本里了）。这里按**当前锁定版本**的真实签名写，编译得过才算数。
//
// JS 模式用 unrestricted（终端前端要跑 JS + WebSocket）。

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';

/// 终端页要用的 Basic 凭据；**没口令时返回 null**，界面改走"先去设置里填"的引导。
///
/// 抽成纯函数是为了能单测：直接构造 WebViewController 需要平台实现，
/// 单测里起不来；凭据怎么算这件事不该只有真机才验证得了。
WebViewCredential? opsTerminalCredential(ServerOpsSettings settings) {
  if (!settings.hasPassword) return null;
  return WebViewCredential(
    user: settings.effectiveUser,
    password: settings.effectivePassword,
  );
}

class ServerOpsTerminalTab extends StatefulWidget {
  const ServerOpsTerminalTab({
    super.key,
    required this.settings,
    this.onOpenSettings,
  });

  final ServerOpsSettings settings;

  /// 引导里的「去设置」按钮回调（由页面提供）。
  final VoidCallback? onOpenSettings;

  @override
  State<ServerOpsTerminalTab> createState() => _ServerOpsTerminalTabState();
}

class _ServerOpsTerminalTabState extends State<ServerOpsTerminalTab> {
  WebViewController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void didUpdateWidget(covariant ServerOpsTerminalTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 口令/地址变了（用户刚在设置里填上）→ 重建 webview，否则一直停在 401。
    if (oldWidget.settings != widget.settings) {
      _setup();
    }
  }

  void _setup() {
    final credential = opsTerminalCredential(widget.settings);
    if (credential == null) {
      _controller = null;
      _loading = false;
      return;
    }
    final url = Uri.tryParse(widget.settings.effectiveTerminalUrl.trim());
    if (url == null || !url.hasScheme) {
      _controller = null;
      _loading = false;
      _error = '终端地址不合法：${widget.settings.effectiveTerminalUrl}';
      return;
    }
    _error = null;
    _loading = true;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF111111))
      ..setNavigationDelegate(
        NavigationDelegate(
          // 401 就发生在这里：不应答就是永远的白屏 + 401。
          onHttpAuthRequest: (request) {
            final cred = opsTerminalCredential(widget.settings);
            if (cred == null) {
              request.onCancel();
              return;
            }
            request.onProceed(cred);
          },
          onNavigationRequest: (request) {
            final target = Uri.tryParse(request.url);
            final scheme = target?.scheme.toLowerCase() ?? '';
            if (scheme == 'http' || scheme == 'https' || scheme == 'about') {
              return NavigationDecision.navigate;
            }
            // 终端里的 telnet:// ssh:// 之类交给系统别在这里崩。
            return NavigationDecision.prevent;
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = '页面加载失败：${error.description}';
            });
          },
        ),
      )
      ..loadRequest(url);
  }

  void _reload() {
    _setup();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return _NeedPassword(
        message: _error ?? '终端需要先配置运维通道口令（构建注入过就不用填）。',
        onOpenSettings: widget.onOpenSettings,
      );
    }
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: Stack(
            children: [
              WebViewWidget(controller: controller),
              if (_error != null)
                Align(
                  alignment: Alignment.topCenter,
                  child: Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          TextButton(
                            onPressed: _reload,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NeedPassword extends StatelessWidget {
  const _NeedPassword({required this.message, this.onOpenSettings});

  final String message;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.key_off_rounded,
              size: 44,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text(
              '还没配置终端口令',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('去设置'),
            ),
          ],
        ),
      ),
    );
  }
}

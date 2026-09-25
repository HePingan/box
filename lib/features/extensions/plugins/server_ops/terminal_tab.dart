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
//
// 290 (A6) 加了三样，让终端从"能看"变成"能用"：
//   1. 底部辅助键栏（Ctrl / Tab / 方向键 / 粘贴）——手机上没这些键，
//      改配置、翻历史、中断命令都得靠它；
//   2. 断线提示与「重连」——原来断了就白屏，现在给分型的**人话原因**；
//   3. 字号设置（存 SharedPreferences，前缀 serverOps.term.）。
// 三者的**纯逻辑**都在 terminal_controls.dart 里单测（WebView 上不了单测）；
// 真机上 ttyd 是否照单接收注入事件属于"未验证"，见方案 A6 的验收标准。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_request_log.dart';
import 'package:box/features/extensions/plugins/server_ops/terminal_controls.dart';

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

/// 页面 20 秒还没 onPageFinished 就当卡住了（onWebResourceError 不一定会来）。
const Duration terminalWatchdogTimeout = Duration(seconds: 20);

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
  double _fontSize = terminalFontSizeDefault;

  /// Ctrl 是"一次性修饰键"：点一次亮起来，按下下一个键时带上 Ctrl 并自动熄灭。
  /// 做成开关会让人忘了自己开着 Ctrl，然后在终端里敲出莫名其妙的控制字符。
  bool _ctrlArmed = false;

  Timer? _watchdog;

  /// A9：本次加载的开始时刻（算耗时用）。
  DateTime? _loadStarted;

  @override
  void initState() {
    super.initState();
    _loadFontSize();
    _setup();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ServerOpsTerminalTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 口令/地址变了（用户刚在设置里填上）→ 重建 webview，否则一直停在 401。
    if (oldWidget.settings != widget.settings) {
      _setup();
    }
  }

  /// 读本地字号。读完顺手注入一次（页面可能已经加载好了）。
  Future<void> _loadFontSize() async {
    final size = await loadTerminalFontSize();
    if (!mounted) return;
    setState(() => _fontSize = size);
    _applyFontSize();
  }

  void _setup() {
    _watchdog?.cancel();
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
    _loadStarted = DateTime.now();
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
            setState(() {
              _loading = false;
              // 页面活了就撤掉断线提示：上一次的失败不该挂在新页面上。
              _error = null;
            });
            _logTerminal(true, '页面已加载');
            _applyFontSize();
          },
          onWebResourceError: (error) {
            // 子资源（字体/图标）失败一天好几次，弹成"断线"只会让人忽略提示。
            if (!terminalErrorIsFatal(error)) return;
            if (!mounted) return;
            _watchdog?.cancel();
            setState(() {
              _loading = false;
              _error = terminalErrorHint(error);
            });
            _logTerminal(false, terminalErrorHint(error));
          },
        ),
      )
      ..loadRequest(url);
    // onWebResourceError 只在"连接层就失败了"时来；卡在认证 / nginx 转发上时
    // 一声不响。加一条兜底，否则用户面对的还是那块没有解释的白屏。
    _watchdog = Timer(terminalWatchdogTimeout, () {
      if (!mounted) return;
      if (!_loading) return;
      setState(() {
        _loading = false;
        _error = terminalWatchdogHint;
      });
      _logTerminal(false, terminalWatchdogHint);
    });
  }

  /// A9：终端页的结果也进请求日志。
  ///
  /// 终端是 WebView，**拿不到状态码**（除了 401 那种由 WebView 内部握手的），
  /// 所以这里记的是"页面已加载 / 失败原因 / 20 秒超时"这三种人话结论 —— 正是真机
  /// 反馈里最缺的那一格。
  void _logTerminal(bool ok, String detail) {
    final s = widget.settings.currentServer;
    final started = _loadStarted ?? DateTime.now();
    serverOpsRequestLog.record(
      OpsRequestRecord(
        entry: '终端',
        serverId: s.id,
        serverLabel: s.label,
        ok: ok,
        detail: detail,
        duration: DateTime.now().difference(started),
        at: started,
      ),
    );
  }

  void _reload() {
    _setup();
    setState(() {});
  }

  /// 把当前字号注入页面。页面还没渲染出 .xterm 时注入会返回 false —— 无害，
  /// onPageFinished 里还会再来一次。
  void _applyFontSize() {
    final controller = _controller;
    if (controller == null) return;
    unawaited(controller.runJavaScript(terminalFontScaleJs(_fontSize)));
  }

  /// 辅助键：往 WebView 里注入一次键盘事件。
  void _sendKey(TerminalAuxKey key) {
    final controller = _controller;
    if (controller == null) return;
    final ctrl = _ctrlArmed;
    unawaited(controller.runJavaScript(terminalAuxKeyJs(key, ctrl: ctrl)));
    if (ctrl) setState(() => _ctrlArmed = false);
  }

  /// Ctrl+C / Ctrl+D 之类：长按 Ctrl 弹层里选的那一个。
  void _sendCtrlCombo(String letter) {
    final controller = _controller;
    if (controller == null) return;
    unawaited(controller.runJavaScript(terminalCtrlComboJs(letter)));
    if (_ctrlArmed) setState(() => _ctrlArmed = false);
  }

  /// 粘贴：先从系统剪贴板取文本（Dart 侧做，比在 JS 里读剪贴板可靠得多），
  /// 再注入页面。口令/命令这类长文本靠手打基本不现实。
  Future<void> _paste() async {
    final controller = _controller;
    if (controller == null) return;
    ClipboardData? data;
    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } catch (_) {
      data = null;
    }
    if (!mounted) return;
    final text = data?.text ?? '';
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(terminalClipboardEmptyHint)),
      );
      return;
    }
    unawaited(controller.runJavaScript(terminalPasteJs(text)));
  }

  /// 字号增减：夹边界 → 立即生效 → 落盘（顺序不能反，落盘失败也要生效）。
  void _stepFontSize(double delta) {
    final next = clampTerminalFontSize(_fontSize + delta);
    if (next == _fontSize) return;
    setState(() => _fontSize = next);
    unawaited(saveTerminalFontSize(next));
    _applyFontSize();
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
        _toolbar(context),
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
                            child: const Text('重连'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_error == null)
          TerminalAuxBar(
            ctrlArmed: _ctrlArmed,
            onToggleCtrl: () => setState(() => _ctrlArmed = !_ctrlArmed),
            onKey: _sendKey,
            onPaste: _paste,
            onCtrlCombo: _sendCtrlCombo,
          ),
      ],
    );
  }

  /// 顶部一条细工具条：字号增减 + 重新加载。
  ///
  /// 辅助键栏放在**底部**（拇指够得到），字号这类"偶尔调一次"的放顶部，
  /// 免得跟辅助键抢那点高度。
  Widget _toolbar(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            const SizedBox(width: 8),
            Text(
              _ctrlArmed ? 'Ctrl 已待命' : '辅助键',
              style: theme.textTheme.labelSmall,
            ),
            const Spacer(),
            IconButton(
              tooltip: '缩小字号',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: _fontSize > terminalFontSizeMin
                  ? () => _stepFontSize(-1)
                  : null,
              icon: const Icon(Icons.text_decrease_rounded),
            ),
            Text(
              '${_fontSize.round()}',
              style: theme.textTheme.labelSmall,
            ),
            IconButton(
              tooltip: '放大字号',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: _fontSize < terminalFontSizeMax
                  ? () => _stepFontSize(1)
                  : null,
              icon: const Icon(Icons.text_increase_rounded),
            ),
            IconButton(
              tooltip: '重新加载',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部辅助键栏。抽成公开 widget 是因为**它能被 widget 测试**（不需要 WebView）：
/// 要验证的正是"点哪个键回调哪个键"，而 WebView 在单测里起不来。
class TerminalAuxBar extends StatelessWidget {
  const TerminalAuxBar({
    super.key,
    required this.ctrlArmed,
    required this.onToggleCtrl,
    required this.onKey,
    required this.onPaste,
    required this.onCtrlCombo,
  });

  /// Ctrl 是否已待命（点亮状态由父级持有，见 `_ctrlArmed` 的说明）。
  final bool ctrlArmed;

  final VoidCallback onToggleCtrl;

  /// 按下了某一个辅助键——带不带 Ctrl 由父级按 [ctrlArmed] 决定。
  final void Function(TerminalAuxKey key) onKey;

  final VoidCallback onPaste;

  /// 长按 Ctrl 弹层里选了 Ctrl+字母。
  final void Function(String letter) onCtrlCombo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            children: [
              _AuxButton(
                label: 'Ctrl',
                tooltip: '点一次＝下一个键带 Ctrl（长按选 Ctrl+C 等组合）',
                highlighted: ctrlArmed,
                onPressed: onToggleCtrl,
                onLongPress: () => _showCtrlCombos(context),
              ),
              for (final key in TerminalAuxKey.values)
                _AuxButton(
                  label: key.label,
                  onPressed: () => onKey(key),
                ),
              _AuxButton(
                label: '粘贴',
                icon: Icons.content_paste_rounded,
                onPressed: onPaste,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCtrlCombos(BuildContext context) async {
    final letter = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              dense: true,
              title: Text(
                'Ctrl 组合键',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final (letter, label) in terminalCtrlCombos)
              ListTile(
                dense: true,
                title: Text(label),
                onTap: () => Navigator.pop(sheetContext, letter),
              ),
          ],
        ),
      ),
    );
    if (letter != null) onCtrlCombo(letter);
  }
}

class _AuxButton extends StatelessWidget {
  const _AuxButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.tooltip,
    this.highlighted = false,
    this.onLongPress,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final String? tooltip;
  final bool highlighted;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final button = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      child: highlighted
          ? FilledButton.tonal(
              onPressed: onPressed,
              onLongPress: onLongPress,
              child: _child(),
            )
          : OutlinedButton(
              onPressed: onPressed,
              onLongPress: onLongPress,
              child: _child(),
            ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }

  Widget _child() {
    if (icon == null) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 16), const SizedBox(width: 4), Text(label)],
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

// 服务器运维插件：「终端」页的**纯逻辑**——辅助键注入 / 字号 / 断线原因。
//
// 为什么单开这个文件：终端页的交互全靠 WebView，而 WebView 在单测里起不来
// （没有平台实现，构造 WebViewController 直接抛）。所以把三件本来只靠真机
// 才能知道对错的事抽成不依赖平台、不依赖网络的纯函数，让它们能被真正验证：
//
//   1. 辅助键（Ctrl / Tab / 方向键 / 粘贴）→ 注入 ttyd 页面的 JS 片段；
//   2. 字号解析与边界 + 本地持久化的键名（前缀 `serverOps.term.`）；
//   3. `WebResourceError` → 机制上分得清的中文人话（不是笼统的"加载失败"）。
//
// **明确不在单测覆盖范围内**：真机上 ttyd（xterm.js）前端是否照单接收这些
// 合成事件、zoom 是否让画布同步缩放——那只能在真机上看（方案 A6 的验收标准
// 本来就写了"真机截图"）。这里保证的是"我们发出去的指令是对的"。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 辅助键栏里那些"按一下等于敲一下"的键（**不含 Ctrl**：它不是一次按键，
/// 是作用于下一个按键的修饰状态；也不含粘贴：它要先从系统剪贴板取内容）。
enum TerminalAuxKey {
  tab('Tab', 'Tab', 9),
  arrowUp('↑', 'ArrowUp', 38),
  arrowDown('↓', 'ArrowDown', 40),
  arrowLeft('←', 'ArrowLeft', 37),
  arrowRight('→', 'ArrowRight', 39);

  const TerminalAuxKey(this.label, this.jsKey, this.keyCode);

  /// 按钮上的字。
  final String label;

  /// 注入时给 KeyboardEvent 的 `key` / `code`（xterm.js 按 `key` 判定序列）。
  final String jsKey;

  /// 传统 keyCode（老浏览器与部分前端仍读它）。
  final int keyCode;
}

/// ttyd 用 xterm.js，键盘输入落在这个隐藏 textarea 上。
/// 合成事件必须发给它，而不是 `document`——xterm 只监听自己的 textarea。
const String terminalInputSelector = '.xterm-helper-textarea';

/// 所有注入片段的开头：找到 xterm 的输入框并聚焦。
///
/// 没找到输入框时返回 false（而不是抛）：页面可能还没渲染完，
/// 这时静默失败比让 runJavaScript 抛一个看不懂的异常好。
const String _focusHelperJs = '''
(function () {
  var t = document.querySelector("$terminalInputSelector");
  if (!t) { t = document.activeElement; }
  if (!t) { return false; }
  t.focus();
''';

/// 辅助键 → 注入片段。[ctrl] 为 true 时带上 Ctrl 修饰（Ctrl+Tab / Ctrl+← 等）。
///
/// keydown + keyup 都要发：xterm 在 keydown 上生成序列，但只发 keydown
/// 会让前端以为这个键一直按着（影响自动重复与修饰状态）。
String terminalAuxKeyJs(TerminalAuxKey key, {bool ctrl = false}) {
  final init = _keyEventInit(
    key: key.jsKey,
    code: key.jsKey,
    keyCode: key.keyCode,
    ctrl: ctrl,
  );
  return '''
$_focusHelperJs
  var init = $init;
  t.dispatchEvent(new KeyboardEvent("keydown", init));
  t.dispatchEvent(new KeyboardEvent("keyup", init));
  return true;
})();
''';
}

/// Ctrl + 单个字母（长按 Ctrl 弹层里的 C / D / Z / L …）。
///
/// 大小写都收，统一按小写注入：终端的 Ctrl-C 与 Ctrl-Shift-C 不是一回事，
/// 但用户点的是"Ctrl+C"这个意图，xterm 只认 `key: 'c' + ctrlKey`。
String terminalCtrlComboJs(String letter) {
  final normalized = letter.trim().toLowerCase();
  if (normalized.length != 1) {
    throw ArgumentError.value(letter, 'letter', 'Ctrl 组合只支持单个字母');
  }
  final code = 'Key${normalized.toUpperCase()}';
  final keyCode = normalized.toUpperCase().codeUnitAt(0);
  final init = _keyEventInit(
    key: normalized,
    code: code,
    keyCode: keyCode,
    ctrl: true,
  );
  return '''
$_focusHelperJs
  var init = $init;
  t.dispatchEvent(new KeyboardEvent("keydown", init));
  t.dispatchEvent(new KeyboardEvent("keyup", init));
  return true;
})();
''';
}

/// 粘贴：[text] 由 Dart 侧从系统剪贴板取出后传进来。
///
/// 三级兜底，因为 ttyd 的版本差异会让其中某一条不生效：
///   1. `term.paste()`——ttyd 把 xterm 实例挂在 window 上时最干净；
///   2. `execCommand('insertText')`——会触发 xterm 监听的 `input` 事件；
///   3. 直接写 textarea 并手动派发 `input`——前两步都不行时的最后手段。
String terminalPasteJs(String text) {
  final literal = jsonEncode(text);
  return '''
(function () {
  var text = $literal;
  if (!text) { return false; }
  if (typeof window.term !== "undefined" && window.term &&
      typeof window.term.paste === "function") {
    window.term.paste(text);
    return true;
  }
  var t = document.querySelector("$terminalInputSelector");
  if (!t) { t = document.activeElement; }
  if (!t) { return false; }
  t.focus();
  if (document.execCommand && document.execCommand("insertText", false, text)) {
    return true;
  }
  t.value = text;
  t.dispatchEvent(new Event("input", { bubbles: true }));
  return true;
})();
''';
}

/// 字号 → 注入片段。
///
/// 直接改 `.xterm` 的 `font-size` 对 canvas 渲染器无效（字是画进画布的），
/// 所以用 CSS `zoom` 把整个终端等比缩放——Chromium WebView 支持，
/// 画布与滚动区域会一起跟着变。缩放前后各派发一次 `resize`，让 xterm
/// 重算行列数，否则会画出格。
String terminalFontScaleJs(double fontSize) {
  final ratio = clampTerminalFontSize(fontSize) / terminalFontSizeDefault;
  return '''
(function () {
  var root = document.querySelector(".xterm");
  if (!root) { return false; }
  root.style.zoom = "${ratio.toStringAsFixed(3)}";
  window.dispatchEvent(new Event("resize"));
  return true;
})();
''';
}

/// KeyboardEvent 的 init 字典。keyCode/which 在现代浏览器里是只读的（传进去
/// 会被忽略），但老 WebView 仍读它，所以照传——xterm 的文法补全依赖
/// `key` 而非 keyCode，两处都给上最保险。
String _keyEventInit({
  required String key,
  required String code,
  required int keyCode,
  required bool ctrl,
}) {
  return '{key: ${jsonEncode(key)}, code: ${jsonEncode(code)}, '
      'keyCode: $keyCode, which: $keyCode, ctrlKey: $ctrl, '
      'bubbles: true, cancelable: true}';
}

// ── 字号：解析 / 边界 / 持久化 ────────────────────────────────────

/// 本地键前缀（方案 A6 指定）：与 `serverOps.dav.*` 分开，清档时互不牵连。
const String terminalFontSizeKey = 'serverOps.term.fontSize';

const double terminalFontSizeDefault = 14;
const double terminalFontSizeMin = 9;
const double terminalFontSizeMax = 28;

/// 夹到可用区间。上下界不是拍脑袋：9 以下手机上无法辨认，28 以上
/// ttyd 的 80 列在一屏里塞不下反而更难看。NaN / 无穷也在这里被兜掉。
double clampTerminalFontSize(double value) {
  if (value.isNaN || value.isInfinite) return terminalFontSizeDefault;
  if (value < terminalFontSizeMin) return terminalFontSizeMin;
  if (value > terminalFontSizeMax) return terminalFontSizeMax;
  return value;
}

/// 从 SharedPreferences 读回来的原始值 → 字号。
///
/// 老版本可能存过 `int`，也有可能被人手改成脏字符串；一律解析不了就用默认值，
/// **不抛异常**——一个字号坏了不该让整个终端页打不开。
double parseTerminalFontSize(Object? raw) {
  if (raw is num) return clampTerminalFontSize(raw.toDouble());
  if (raw is String) {
    final parsed = double.tryParse(raw.trim());
    if (parsed != null) return clampTerminalFontSize(parsed);
  }
  return terminalFontSizeDefault;
}

/// 读已保存的字号；读不出来（首次安装 / 存储异常）用默认值。
Future<double> loadTerminalFontSize() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return parseTerminalFontSize(prefs.getString(terminalFontSizeKey));
  } catch (_) {
    return terminalFontSizeDefault;
  }
}

/// 存字号（夹过界再存，避免把 999 落到盘上）。
Future<void> saveTerminalFontSize(double fontSize) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      terminalFontSizeKey,
      clampTerminalFontSize(fontSize).toString(),
    );
  } catch (_) {
    // 存不下不影响本次会话（内存里的字号已经生效），别让保存失败弹红。
  }
}

// ── 断线：WebResourceError → 中文人话 ─────────────────────────────

/// 长按 Ctrl 弹出的组合键清单：字母 + 用途（终端里最常用的十个）。
///
/// 放进 UI 的前端而不是硬编码在按钮里：这些是"用户真正要敲的动作"，
/// 加一条不用动界面代码；单测也能直接遍历它对每条跑一遍注入片段。
const List<(String, String)> terminalCtrlCombos = <(String, String)>[
  ('c', 'Ctrl+C 中断当前命令'),
  ('d', 'Ctrl+D 结束输入 / 登出'),
  ('z', 'Ctrl+Z 挂起当前进程'),
  ('l', 'Ctrl+L 清屏'),
  ('a', 'Ctrl+A 光标到行首'),
  ('e', 'Ctrl+E 光标到行尾'),
  ('u', 'Ctrl+U 删到行首'),
  ('k', 'Ctrl+K 删到行尾'),
  ('w', 'Ctrl+W 删掉前一个词'),
  ('r', 'Ctrl+R 反向搜索历史'),
];

/// 这个错误值不值得告诉用户。
///
/// ttyd 页面里的图标 / 字体等子资源失败一天要发生好几次，把那些也弹成
/// "断线"只会让人忽略提示。只有主文档（`isForMainFrame != false`，未知时
/// 按主文档处理，宁可多报一条也别漏掉真正的断线）才算。
bool terminalErrorIsFatal(WebResourceError error) =>
    error.isForMainFrame != false;

/// 错误 → 用户看得懂的一句中文 + 可操作的建议。
///
/// 分型的依据是"用户下一步该改什么"：网络问题、口令问题、地址写错、
/// 系统回收 WebView —— 四类完全不同的动作，不能都叫"加载失败"。
String terminalErrorHint(WebResourceError error) {
  final tail = error.description.isEmpty ? '' : '（${error.description}）';
  switch (error.errorType) {
    case WebResourceErrorType.timeout:
      return '终端连接超时：服务器一直没回话，多半是网络慢或被拦。$tail 点「重连」再试一次。';
    case WebResourceErrorType.connect:
    case WebResourceErrorType.hostLookup:
      return '连不上终端服务器：域名解析或端口不通。$tail 检查手机网络与设置里的终端地址，再点「重连」。';
    case WebResourceErrorType.failedSslHandshake:
      return '证书校验没通过：HTTPS 握手失败。$tail 自签证书要先在系统里信任。';
    case WebResourceErrorType.authentication:
      return '认证被拒：口令不对。$tail 到设置里重填运维通道口令。';
    case WebResourceErrorType.unsupportedAuthScheme:
      return '认证方式不支持：服务端要的不是 Basic。$tail 需要在 nginx 侧改成 Basic 认证。';
    case WebResourceErrorType.fileNotFound:
    case WebResourceErrorType.file:
      return '终端页面不存在：地址可能写错了。$tail 检查设置里的终端地址（要以 / 结尾）。';
    case WebResourceErrorType.redirectLoop:
      return '重定向打转：地址被反复改写。$tail 检查 nginx 的终端 location 配置。';
    case WebResourceErrorType.io:
      return '与服务端的连接中断了（终端多半已断开）。$tail 点「重连」重新建立会话。';
    case WebResourceErrorType.webContentProcessTerminated:
      return '渲染进程被系统终止了（内存不足时最常见）。$tail 点「重连」重新加载终端。';
    case WebResourceErrorType.webViewInvalidated:
      return 'WebView 被系统回收了：切回来需要重建。$tail 点「重连」重新加载终端。';
    case WebResourceErrorType.tooManyRequests:
      return '请求太频繁被服务端挡了（429）。$tail 稍等一会儿再点「重连」。';
    case WebResourceErrorType.javaScriptExceptionOccurred:
    case WebResourceErrorType.javaScriptResultTypeIsUnsupported:
      return '终端前端脚本出错：页面自己的问题。$tail 点「重连」重载页面。';
    case WebResourceErrorType.badUrl:
      return '终端地址不是合法 URL。$tail 到设置里改地址。';
    case WebResourceErrorType.unsupportedScheme:
      return '地址的协议不支持：终端要用 http/https。$tail 到设置里改地址。';
    case WebResourceErrorType.proxyAuthentication:
      return '代理认证失败。$tail 检查手机代理设置。';
    case WebResourceErrorType.unsafeResource:
      return '资源被安全策略拦了。$tail 点「重连」重试。';
    case WebResourceErrorType.unknown:
    case null:
      return '终端页面加载失败$tail。点「重连」重试；反复失败就到设置里先跑一次「测试连接」。';
  }
}

/// 页面迟迟不响应时的兜底提示（`onWebResourceError` 不一定来，见 A6 备注）。
const String terminalWatchdogHint =
    '终端页面迟迟没加载出来（20 秒无响应）：可能卡在认证或 nginx 转发上。'
    '点「重连」重试，或到设置里跑一次「测试连接」。';

/// 剪贴板里没有可粘贴的文本时的提示。
const String terminalClipboardEmptyHint = '剪贴板里没有文本可粘贴。';

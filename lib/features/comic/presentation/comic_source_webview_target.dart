// 真机取数：驱动一个**不可见的 WebView**去打开页面、跑 JS 取值。
//
// 为什么必须在 WebView 里做：站点有 JS 人机挑战，纯 HTTP 一律 403；而且书源规则里
// 有 `<js>` / `@js:` 段 —— Dart 没有 JS 求值能力，WebView 有（Legado 自己也是这么做的）。
//
// WebView 是**离屏**的：1×1 放在页面角落、不可点、几乎全透明。它照样会加载、执行 JS、
// 过挑战；用户看不到它。这也是"自检"这一步敢跑真页面的原因。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../domain/comic_source_diagnostics.dart';
import '../domain/comic_source_engine.dart';

/// 隐藏 WebView 的控制器 + 取数实现（合成一个对象，页面只管把它交给自检）。
class ComicSourceWebViewController {
  ComicSourceWebViewController() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            // 页面加载"完成"并不等于挑战过了、内容渲染好了；真正的等待由
            // waitForCount 轮询选择器来完成（这里只取消这一轮的等待）。
            _pageDone?.complete();
          },
          onWebResourceError: (error) {
            // 只认**主文档**的失败：图片/统计脚本这类子资源失败不该让整步判死
            // （站点的广告位天天挂）。null 表示平台没说清，按"不是主文档"处理，
            // 最终仍由"选择器有没有命中"来判 —— 不让一个不确定的错误码背锅。
            final isMain = error.isForMainFrame ?? false;
            if (!isMain) {
              _subResourceErrors++;
              return;
            }
            _lastLoadError = ComicLoadFailure(
              code: error.errorCode,
              description: error.description,
            );
          },
        ),
      );
  }

  late final WebViewController controller;
  Completer<void>? _pageDone;
  ComicLoadFailure? _lastLoadError;

  /// 子资源（图片/脚本）失败次数：不影响判定，只在需要时说明。
  int _subResourceErrors = 0;

  ComicLoadFailure? get lastLoadError => _lastLoadError;
  int get subResourceErrorCount => _subResourceErrors;

  WebViewComicSourceTarget get target => WebViewComicSourceTarget(this);

  /// 离屏 WebView。放在 1×1 的位置上，别让它抢页面布局或点击。
  Widget buildOffscreen() {
    return Positioned(
      left: -2,
      top: -2,
      width: 1,
      height: 1,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.01,
          child: WebViewWidget(controller: controller),
        ),
      ),
    );
  }
}

/// 取数实现。**任何失败都抛**，不吞成空 —— 自检要的就是原因。
class WebViewComicSourceTarget implements ComicSourceTarget {
  WebViewComicSourceTarget(this._owner);

  final ComicSourceWebViewController _owner;

  @override
  Future<void> open(String url, {Map<String, String>? headers}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw ComicProbeException('地址不合法：$url');
    }
    _owner._lastLoadError = null;
    _owner._pageDone = Completer<void>();
    try {
      await _owner.controller.loadRequest(uri, headers: headers ?? const {});
    } catch (e) {
      throw ComicProbeException('发起加载失败：$e');
    }
    // 等"加载完成"或超时；超时不抛 —— 有些站点永远不上报完成，
    // 后面靠选择器轮询判断，这里只是给页面一个起步的机会。
    try {
      await _owner._pageDone!.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      // 继续往下走：真正的判据是选择器有没有命中。
    }
    // 主文档加载错误**不在这里抛**：交给自检流程判种类（重试 / 换镜像 / 直接停），
    // 由它决定下一步，并把每一条尝试如实报出来。
  }

  @override
  ComicLoadFailure? get lastLoadError => _owner.lastLoadError;

  @override
  Future<String> currentUrl() async {
    final u = await _owner.controller.currentUrl();
    return u ?? '';
  }

  @override
  Future<String> pageTitle() async {
    // 别用 replaceAll 删引号：Android 会把 `<` 之类转义（\u003C），得按 JSON 解层再还原。
    return comicText(await evalRaw('javascript:document.title')) ?? '';
  }

  @override
  Future<int> countOf(String css) async {
    final v = parseComicJsValue(await evalRaw(buildComicCountScript(css)));
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  @override
  Future<String?> attrOf(String css, String attr) async =>
      comicText(await evalRaw(buildComicAttrScript(css, attr)));

  @override
  Future<List<String>> attrsOf(String css, String attr) async {
    final raw = await evalRaw(buildComicAttrsScript(css, attr));
    // 转义由 parseComicJsValue 统一还原（Android 会再编码一层）。
    return comicAttrList(raw);
  }

  @override
  Future<String?> sampleHtml(String css) async {
    // 不要把引号删掉 —— 片段是给人看的，`src="…"` 比 `src=…` 有用得多。
    return comicText(await evalRaw(buildComicSampleScript(css)));
  }

  @override
  Future<String> fetchInPage(
    String url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await evalRaw(buildComicFetchStartScript(url, headers));
    final sw = Stopwatch()..start();
    while (sw.elapsed < timeout) {
      final raw = await evalRaw(buildComicFetchStateScript());
      final v = parseComicJsValue(raw);
      final m = v is Map ? v : const {};
      final state = m['state']?.toString() ?? '';
      if (state == 'ok') return m['body']?.toString() ?? '';
      if (state == 'err') {
        throw ComicProbeException(
          '在页面里取接口失败：${m['body']}（这样发请求被站点拒了的话，多半是它的反爬拦了）',
        );
      }
      if (state == 'none') {
        throw ComicProbeException('页面里没能发起请求（WebView 可能还没就绪）');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw ComicProbeException('在页面里取接口超时（等了 ${timeout.inSeconds} 秒）');
  }

  @override
  Future<String> evalRaw(String script) async {
    // 类型上不可能是 null（webview_flutter 的返回是 Object）；
    // 页面里拿到 undefined 时会变成字符串 "null"，由调用方按"取不到"处理。
    final result = await _owner.controller.runJavaScriptReturningResult(script);
    return result.toString();
  }
}

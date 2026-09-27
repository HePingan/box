// 漫画取自检/在线服务的公共假目标。
//
// **按真机形状回答**：Android 的 `runJavaScriptReturningResult` 会把 JS 返回的字符串
// 再 JSON 编码一层（引号 → `\"`、`<` → `\u003C`）。假目标必须照这个形状返回，
// 否则单测测的是"我以为的形状"，真机就会红（这个坑踩过一次）。
library;

import 'dart:convert';

import 'package:box/features/comic/domain/comic_source_diagnostics.dart'
    show ComicLoadFailure, ComicSourceTarget;
import 'package:box/features/comic/domain/comic_source_engine.dart';

/// 模拟 Android 的返回：WebView 会把 JS 返回的字符串再 JSON 编码一层。
String androidEncode(String jsonText) => jsonEncode(jsonText)
    .replaceAll('<', r'\u003C')
    .replaceAll('>', r'\u003E');

/// 假取数实现：按脚本形状回答（与引擎真实返回同形）。
class FakeComicTarget implements ComicSourceTarget {
  FakeComicTarget({
    this.perElement = const {},
    this.values = const {},
    this.jsSegment = '',
    this.attrs = const {},
    this.counts = const {},
    this.hrefs = const {},
    Map<String, String> responses = const {},
    this.failOpen = false,
  }) : responses = {...responses}; // 可变副本：用例可以后面再补响应

  /// key: `卡片规则|字段规则` → 每卡片的值。
  final Map<String, List<String>> perElement;

  /// key: 整页规则 → 值列表。
  final Map<String, List<String>> values;

  /// 书源 JS 段返回的 HTML（原样，未编码）。
  final String jsSegment;

  /// key: `css|属性` → 属性值列表。
  final Map<String, List<String>> attrs;

  /// key: css → 命中数。
  final Map<String, int> counts;

  /// key: css → 链接（`a[href]` 直取）。
  final Map<String, List<String>> hrefs;

  /// key: 请求地址 → 响应体（原样，未编码）。页面内请求（分类榜单一类）用。
  final Map<String, String> responses;

  final bool failOpen;

  /// 前 N 次轮询返回命中数 0（模拟"列表还没渲染出来"）。
  int countsEmptyFirstNPolls = 0;
  final Map<String, int> _countPolls = {};

  final List<String> opened = [];

  /// 在页面里**发过的请求**地址（页面内 fetch，不是打开页面）。
  final List<String> fetched = [];

  @override
  Future<void> open(String url, {Map<String, String>? headers}) async {
    if (failOpen) throw ComicProbeException('打不开：$url');
    opened.add(url);
  }

  @override
  ComicLoadFailure? get lastLoadError => null;

  @override
  Future<String> currentUrl() async => opened.isEmpty ? '' : opened.last;

  @override
  Future<String> pageTitle() async => '假页面';

  @override
  Future<int> countOf(String css) async {
    final n = (_countPolls[css] ?? 0) + 1;
    _countPolls[css] = n;
    if (n <= countsEmptyFirstNPolls) return 0;
    return counts[css] ?? 0;
  }

  @override
  Future<String?> attrOf(String css, String attr) async =>
      attrs['$css|$attr']?.firstOrNull;

  @override
  Future<List<String>> attrsOf(String css, String attr) async =>
      attrs['$css|$attr'] ?? const [];

  @override
  Future<String?> sampleHtml(String css) async => null;

  @override
  Future<String> fetchInPage(
    String url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 15),
  }) async {
    fetched.add(url);
    final body = responses[url];
    if (body == null) {
      throw ComicProbeException('假目标没准备这个地址的响应：$url');
    }
    return body;
  }

  @override
  Future<String> evalRaw(String script) async {
    // 按卡片取字段
    final per = RegExp(
      r'legadoExtractInEach\(("(?:[^"\\]|\\.)*"), ("(?:[^"\\]|\\.)*")\)',
    ).firstMatch(script);
    if (per != null) {
      final card = jsonDecode(per.group(1)!) as String;
      final field = jsonDecode(per.group(2)!) as String;
      final list = perElement['$card|$field'] ?? const <String>[];
      return androidEncode(jsonEncode({'values': list}));
    }
    // 整页取值
    final rule = RegExp(
      r'legadoExtract\(("(?:[^"\\]|\\.)*")\)',
    ).firstMatch(script);
    if (rule != null) {
      final r = jsonDecode(rule.group(1)!) as String;
      final list = values[r] ?? const <String>[];
      return androidEncode(jsonEncode({'values': list}));
    }
    // 属性直读
    final attrsMatch = RegExp(
      r'querySelectorAll\(("(?:[^"\\]|\\.)*")\)[\s\S]*?getAttribute\(("(?:[^"\\]|\\.)*")\)',
    ).firstMatch(script);
    if (attrsMatch != null) {
      final css = jsonDecode(attrsMatch.group(1)!) as String;
      final attr = jsonDecode(attrsMatch.group(2)!) as String;
      return androidEncode(
        jsonEncode(attrs['$css|$attr'] ?? const <String>[]),
      );
    }
    // 书源 JS 段
    if (jsSegment.isNotEmpty) {
      return androidEncode(jsonEncode({'text': jsSegment}));
    }
    return androidEncode(jsonEncode({'text': ''}));
  }
}

import 'dart:convert';

import 'package:box/novel/core/novel_http_client.dart';
import 'package:box/novel/core/novel_exceptions.dart';
import 'package:box/novel/core/text_cleaner.dart';

import 'crypto_utils.dart';
import 'json_parser.dart';
import 'regex_applier.dart';
import 'template_renderer.dart';
import 'url_resolver.dart';

/// 规则书源引擎（新版）：按职责拆分后的实例编排器
class RuleEngineV2 {
  RuleEngineV2({
    required this.urlResolver,
    required this.renderer,
    required this.regexApplier,
    required this.jsonParser,
    required this.crypto,
    required this.httpClient,
  });

  factory RuleEngineV2.defaults({NovelHttpClient? httpClient}) {
    return RuleEngineV2(
      urlResolver: const UrlResolver(),
      renderer: const TemplateRenderer(),
      regexApplier: const RegexApplier(),
      jsonParser: const JsonParser(),
      crypto: const CryptoUtils(),
      httpClient: httpClient ?? NovelHttpClient.create(),
    );
  }

  // 兼容旧 API 的静态常量
  static const Duration timeout = Duration(seconds: 15);
  static final RegExp htmlTag = RegExp(r'<[^>]+>');
  static final RegExp chapterTitleCleaner = RegExp(
    r'正文卷\.|正文\.|VIP卷\.|默认卷\.|卷_|VIP章节\.|免费章节\.|章节目录\.|最新章节\.'
    r'|[\(（【].*?[求更票谢乐发订合补加架字修Kk].*?[】）\)]',
  );

  final UrlResolver urlResolver;
  final TemplateRenderer renderer;
  final RegexApplier regexApplier;
  final JsonParser jsonParser;
  final CryptoUtils crypto;
  final NovelHttpClient httpClient;

  // ── 实例方法（新架构推荐） ──

  String resolveStringRule(
    String rule, {
    required dynamic context,
    required dynamic root,
    Map<String, String> vars = const {},
  }) {
    var text = rule.trim();
    if (text.isEmpty) return '';

    text = renderer.renderTemplate(text, context, root, vars: vars);

    String? jsExpr;
    final jsIndex = text.indexOf('@js:');
    if (jsIndex >= 0) {
      jsExpr = text.substring(jsIndex + 4).trim();
      text = text.substring(0, jsIndex);
    }

    final parts = text.split('##');
    final base = parts.first.trim();

    dynamic value = resolveDynamic(
      base,
      context: context,
      root: root,
      vars: vars,
    );

    var out = value?.toString() ?? '';

    for (var i = 1; i < parts.length; i += 2) {
      final regex = parts[i].trim();
      final replacement = i + 1 < parts.length ? parts[i + 1] : '';
      if (regex.isEmpty) continue;

      try {
        out = regexApplier.applyRegexReplacement(out, regex, replacement);
      } catch (_) {}
    }

    if (jsExpr != null && jsExpr.isNotEmpty) {
      out = crypto.evalJs(jsExpr, out);
    }

    return out.trim();
  }

  dynamic resolveDynamic(
    String rule, {
    required dynamic context,
    required dynamic root,
    Map<String, String> vars = const {},
  }) {
    return _resolveDynamic(rule, context: context, root: root, vars: vars);
  }

  dynamic _resolveDynamic(
    String rule, {
    required dynamic context,
    required dynamic root,
    Map<String, String> vars = const {},
  }) {
    var text = rule.trim();
    if (text.isEmpty) return '';

    text = renderer.renderTemplate(text, context, root, vars: vars);

    final jsIndex = text.indexOf('@js:');
    if (jsIndex >= 0) {
      text = text.substring(0, jsIndex);
    }

    final regexIndex = text.indexOf('##');
    if (regexIndex >= 0) {
      text = text.substring(0, regexIndex);
    }

    final value =
        TemplateRenderer.extractPath(context, text) ??
        TemplateRenderer.extractPath(root, text);
    if (value != null) return value;

    if (vars.containsKey(text)) return vars[text]!;

    if (context is Map) {
      final v = TemplateRenderer.mapLookup(context, text);
      if (v != null) return v;
    }
    if (root is Map) {
      final v = TemplateRenderer.mapLookup(root, text);
      if (v != null) return v;
    }

    if (urlResolver.looksLikeRuleExpr(text)) return '';
    return text;
  }

  // ── HTTP 请求 ──

  /// 支持 data:;base64,... 内联数据加载
  Future<String> request(
    String path, {
    String? base,
    required String defaultBaseUrl,
    Map<String, String>? headers,
  }) async {
    // data: URI — 解码 base64 内联数据
    if (urlResolver.isDataUri(path)) {
      return _decodeDataUri(path);
    }

    final uri = urlResolver.resolveUri(
      path,
      base: base,
      defaultBaseUrl: defaultBaseUrl,
    );
    final response = await httpClient.get(
      uri,
      headers: headers,
      timeout: timeout,
    );
    return response.body;
  }

  /// 解析 data: URI，返回解码后的字符串
  String _decodeDataUri(String uri) {
    // 格式: data:[<mediatype>][;base64],<data>
    final comma = uri.indexOf(',');
    if (comma < 0) throw NovelSourceException('无效的 data: URI: 缺少逗号');

    final meta = uri.substring(0, comma);
    final encoded = uri.substring(comma + 1);

    final isBase64 = meta.contains(';base64');
    if (isBase64) {
      try {
        return utf8.decode(base64Decode(encoded));
      } catch (e) {
        throw NovelSourceException('data: URI base64 解码失败: $e');
      }
    }
    // 纯文本 data URI
    return Uri.decodeComponent(encoded);
  }

  dynamic tryDecodeJson(String body) => jsonParser.tryDecodeJson(body);

  Map<String, dynamic> asMap(dynamic value) => jsonParser.asMap(value);

  Map<String, String> parseHeader(dynamic raw) => jsonParser.parseHeader(raw);

  String renderTemplate(
    String input,
    dynamic context,
    dynamic root, {
    Map<String, String> vars = const {},
  }) => renderer.renderTemplate(input, context, root, vars: vars);

  dynamic extractInit(dynamic decoded, Map<String, dynamic> rule) {
    if (rule['init'] == null && rule['eval'] == null) return decoded;

    final initRule = (rule['init'] ?? '').toString();
    if (initRule.trim().isEmpty) return decoded;

    // init 规则（如 "$.data"）通常直接指向响应里的一个对象/数组。
    // 先按「动态求值」拿原生对象 —— 绝不能先 toString()：Dart 的 Map.toString()
    // 产出 `{novelName: 斗罗大陆}` 这种键值无引号的字面量，不是合法 JSON，
    // 再 tryDecodeJson 必然失败并静默回退成整个 decoded，导致 init 形同虚设。
    final resolved = resolveDynamic(
      initRule,
      context: decoded,
      root: decoded,
    );
    if (resolved is Map || resolved is List) return resolved;

    // 少数源把 init 指向一个「内嵌 JSON 字符串」字段（常见于加密/转义响应），
    // 这种才需要走字符串二次解析。
    if (resolved is String) {
      final cleaned =
          resolved.replaceAll(RegExp(r'[\(（][^)]*[\)）]'), '').trim();
      if (cleaned.isEmpty) return decoded;
      try {
        final reparsed = jsonParser.tryDecodeJson(cleaned);
        if (reparsed is Map || reparsed is List) return reparsed;
      } catch (_) {
        // 落到下面统一回退
      }
    }

    return decoded;
  }

  String cleanText(String? text) {
    if (text == null || text.isEmpty) return '';
    return TextCleaner.cleanRaw(text);
  }

  String cleanChapterTitle(String? title) {
    if (title == null || title.isEmpty) return '';
    return title.replaceAll(chapterTitleCleaner, '').trim();
  }

  // ── 列表查找 ──

  List<Map<String, dynamic>> findMaps(
    dynamic node,
    bool Function(Map<String, dynamic>) matcher,
  ) {
    final out = <Map<String, dynamic>>[];

    void walk(dynamic current) {
      if (current is Map) {
        final m = Map<String, dynamic>.from(current);
        if (matcher(m)) out.add(m);
        for (final v in m.values) {
          walk(v);
        }
      } else if (current is List) {
        for (final item in current) {
          walk(item);
        }
      }
    }

    walk(node);
    return out;
  }
}

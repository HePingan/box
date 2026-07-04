import 'dart:convert';

import 'package:box/novel/core/rules/regex_applier.dart';
import 'package:box/novel/core/rules/rule_engine_v2.dart';
import 'package:box/novel/core/rules/template_renderer.dart';
import 'package:box/novel/core/text_cleaner.dart';

/// 规则书源引擎（兼容层）：保持旧 static API 不变，内部委托给 RuleEngineV2
class RuleEngine {
  RuleEngine._();

  // 单例实例，供需要渐进迁移的代码使用
  static final RuleEngineV2 _instance = RuleEngineV2.defaults();

  static RuleEngineV2 get v2 => _instance;

  // ── 保留旧 static API（向后兼容） ──
  // 这些方法会转发到 _instance，但为了向后兼容，仍然保持 static

  static const Duration timeout = Duration(seconds: 15);
  static final RegExp htmlTag = RegExp(r'<[^>]+>');
  static final RegExp chapterTitleCleaner = RegExp(
    r'正文卷\.|正文\.|VIP卷\.|默认卷\.|卷_|VIP章节\.|免费章节\.|章节目录\.|最新章节\.'
    r'|[\(（【].*?[求更票谢乐发订合补加架字修Kk].*?[】）\)]',
  );

  static String normalizeBaseUrlInput(String input) =>
      _instance.urlResolver.normalizeBaseUrlInput(input);

  static bool isAbsoluteUrl(String value) =>
      _instance.urlResolver.isAbsoluteUrl(value);

  static bool looksLikeRuleExpr(String text) =>
      _instance.urlResolver.looksLikeRuleExpr(text);

  static String toAbsoluteUrl(
    String input, {
    String? base,
    required String defaultBaseUrl,
  }) => _instance.urlResolver.toAbsoluteUrl(
    input,
    base: base,
    defaultBaseUrl: defaultBaseUrl,
  );

  static Uri resolveUri(
    String path, {
    String? base,
    required String defaultBaseUrl,
  }) => _instance.urlResolver.resolveUri(
    path,
    base: base,
    defaultBaseUrl: defaultBaseUrl,
  );

  static String absUrl(
    String path, {
    String? base,
    required String defaultBaseUrl,
  }) => _instance.urlResolver.absUrl(
    path,
    base: base,
    defaultBaseUrl: defaultBaseUrl,
  );

  static Future<String> request(
    String path, {
    String? base,
    required String defaultBaseUrl,
    Map<String, String>? headers,
  }) async {
    final uri = _instance.urlResolver.resolveUri(
      path,
      base: base,
      defaultBaseUrl: defaultBaseUrl,
    );
    final response = await _instance.httpClient.get(
      uri,
      headers: headers,
      timeout: timeout,
    );
    return response.body;
  }

  static dynamic tryDecodeJson(String body) =>
      _instance.jsonParser.tryDecodeJson(body);

  static Map<String, dynamic> asMap(dynamic value) =>
      _instance.jsonParser.asMap(value);

  static Map<String, String> parseHeader(dynamic raw) =>
      _instance.jsonParser.parseHeader(raw);

  static String renderTemplate(
    String input,
    dynamic context,
    dynamic root, {
    Map<String, String> vars = const {},
  }) => _instance.renderer.renderTemplate(input, context, root, vars: vars);

  static String resolveStringRule(
    String rule, {
    required dynamic context,
    required dynamic root,
    Map<String, String> vars = const {},
  }) => _instance.resolveStringRule(
    rule,
    context: context,
    root: root,
    vars: vars,
  );

  static dynamic resolveDynamicRule(
    String rule, {
    required dynamic context,
    required dynamic root,
    Map<String, String> vars = const {},
  }) =>
      _instance.resolveDynamic(rule, context: context, root: root, vars: vars);

  static String toStr(dynamic value) =>
      value == null ? '' : value.toString().trim();

  static dynamic extractPath(dynamic root, String expr) =>
      TemplateRenderer.extractPath(root, expr);

  static dynamic mapLookup(dynamic root, String key) =>
      TemplateRenderer.mapLookup(root, key);

  static List<Map<String, dynamic>> findMaps(
    dynamic node,
    bool Function(Map<String, dynamic>) matcher,
  ) => _instance.findMaps(node, matcher);

  static String cleanText(String? text) {
    if (text == null || text.isEmpty) return '';
    return TextCleaner.cleanRaw(text);
  }

  static String cleanChapterTitle(String? title) {
    if (title == null || title.isEmpty) return '';
    return title.replaceAll(chapterTitleCleaner, '').trim();
  }

  static dynamic extractInit(dynamic decoded, Map<String, dynamic> rule) {
    if (rule['init'] == null && rule['eval'] == null) return decoded;
    final data = resolveStringRule(
      rule['init'] ?? '',
      context: decoded,
      root: decoded,
    );
    final cleaned = data.replaceAll(RegExp(r'[\(（][^)]*[\)）]'), '').trim();
    if (cleaned.isEmpty) return decoded;
    try {
      return const JsonDecoder().convert(cleaned);
    } catch (_) {
      return decoded;
    }
  }

  static String applyRegexReplacement(
    String text,
    String pattern,
    String replacement,
  ) {
    if (pattern.isEmpty) return text;
    return const RegexApplier().applyRegexReplacement(
      text,
      pattern,
      replacement,
    );
  }
}

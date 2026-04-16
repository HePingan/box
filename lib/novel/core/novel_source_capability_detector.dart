import 'dart:convert';

import 'novel_source_capability.dart';

class NovelSourceCapabilityDetector {
  static NovelSourceCapabilityReport detect(Map<String, dynamic> json) {
    final sourceName = _toStr(json['bookSourceName']).isNotEmpty
        ? _toStr(json['bookSourceName'])
        : '未命名书源';

    final baseUrl = _toStr(json['bookSourceUrl']);
    final searchUrl = _toStr(json['searchUrl']);
    final exploreUrl = _toStr(json['exploreUrl']);

    final ruleSearch = _asMap(json['ruleSearch']);
    final ruleExplore = _asMap(json['ruleExplore']);
    final ruleBookInfo = _asMap(json['ruleBookInfo']);
    final ruleToc = _asMap(json['ruleToc']);
    final ruleContent = _asMap(json['ruleContent']);

    final isWtzw = _looksLikeWtzwSource(json);

    final featureFlags = <String, bool>{
      'hasAtJs': _containsDeep(json, '@js:'),
      'hasJsBlock': _containsDeep(json, '<js>') || _containsDeep(json, '</js>'),
      'hasJavaAjax': _containsDeep(json, 'java.ajax('),
      'hasJavaMd5': _containsDeep(json, 'java.md5Encode('),
      'hasJavaPut': _containsDeep(json, 'java.put('),
      'hasJavaGet': _containsDeep(json, 'java.get('),
      'hasAtPut': _containsDeep(json, '@put:{'),
      'hasAesDecode':
          _containsDeep(json, 'java.aesBase64DecodeToString(') ||
              _containsDeep(json, 'AES/CBC/PKCS5Padding'),
      'hasExploreMenu': _looksLikeExploreMenu(exploreUrl),
      'hasHeaderAuth': _containsDeep(json, 'Authorization') ||
          _containsDeep(json, 'AUTHORIZATION'),
    };

    final matchedSignals = <String>[];
    final warnings = <String>[];
    final blockers = <String>[];

    void addWarning(String text) {
      final t = text.trim();
      if (t.isEmpty) return;
      if (!warnings.contains(t) && !blockers.contains(t)) {
        warnings.add(t);
      }
    }

    void addBlocker(String text) {
      final t = text.trim();
      if (t.isEmpty) return;
      if (!blockers.contains(t)) {
        blockers.add(t);
      }
      warnings.remove(t);
    }

    if (isWtzw) {
      matchedSignals.add('命中 WTZW 专用适配器');
    } else {
      matchedSignals.add('命中通用 Rule 适配器');
    }

    if (featureFlags['hasExploreMenu'] == true) {
      matchedSignals.add('发现页使用菜单数组配置');
    }

    if (featureFlags['hasAesDecode'] == true) {
      matchedSignals.add('检测到 AES 解密规则');
    }

    if (featureFlags['hasHeaderAuth'] == true) {
      matchedSignals.add('检测到自定义请求头 / 鉴权信息');
    }

    // WTZW 源直接按专用适配器处理
    if (isWtzw) {
      final supportsSearch = searchUrl.trim().isNotEmpty;
      final supportsExplore = exploreUrl.trim().isNotEmpty;
      const supportsDetail = true;
      const supportsToc = true;
      const supportsContent = true;

      return NovelSourceCapabilityReport(
        sourceName: sourceName,
        baseUrl: baseUrl,
        adapterKind: NovelSourceAdapterKind.wtzw,
        adapterLabel: 'WTZW 专用适配器',
        supportsSearch: supportsSearch,
        supportsExplore: supportsExplore,
        supportsDetail: supportsDetail,
        supportsToc: supportsToc,
        supportsContent: supportsContent,
        featureFlags: featureFlags,
        matchedSignals: matchedSignals,
        warnings: warnings,
        blockers: blockers,
      );
    }

    // -------- 通用 Rule 检测 --------

    final searchUrlCheck = _checkField(
      'searchUrl',
      searchUrl,
      critical: true,
    );

    final searchBookListCheck = _checkField(
      'ruleSearch.bookList',
      _toStr(ruleSearch['bookList']),
      critical: true,
    );

    final searchBookUrlCheck = _checkField(
      'ruleSearch.bookUrl',
      _toStr(ruleSearch['bookUrl']),
      critical: false,
    );

    final exploreUrlCheck = _checkExploreUrlField(exploreUrl);

    final exploreBookListCheck = _checkField(
      ruleExplore.isNotEmpty ? 'ruleExplore.bookList' : 'ruleSearch.bookList',
      ruleExplore.isNotEmpty
          ? _toStr(ruleExplore['bookList'])
          : _toStr(ruleSearch['bookList']),
      critical: false,
    );

    final exploreBookUrlCheck = _checkField(
      ruleExplore.isNotEmpty ? 'ruleExplore.bookUrl' : 'ruleSearch.bookUrl',
      ruleExplore.isNotEmpty
          ? _toStr(ruleExplore['bookUrl'])
          : _toStr(ruleSearch['bookUrl']),
      critical: false,
    );

    final detailInitCheck = _checkField(
      'ruleBookInfo.init',
      _toStr(ruleBookInfo['init']),
      critical: false,
      allowEmpty: true,
    );

    final tocUrlCheck = _checkField(
      'ruleBookInfo.tocUrl',
      _toStr(ruleBookInfo['tocUrl']),
      critical: false,
      allowEmpty: true,
    );

    final chapterListCheck = _checkField(
      'ruleToc.chapterList',
      _toStr(ruleToc['chapterList']),
      critical: true,
    );

    final chapterUrlCheck = _checkField(
      'ruleToc.chapterUrl',
      _toStr(ruleToc['chapterUrl']),
      critical: true,
    );

    final contentCheck = _checkField(
      'ruleContent.content',
      _toStr(ruleContent['content']),
      critical: true,
    );

    final allChecks = <_FieldCheckResult>[
      searchUrlCheck,
      searchBookListCheck,
      searchBookUrlCheck,
      exploreUrlCheck,
      exploreBookListCheck,
      exploreBookUrlCheck,
      detailInitCheck,
      tocUrlCheck,
      chapterListCheck,
      chapterUrlCheck,
      contentCheck,
    ];

    for (final check in allChecks) {
      if (check.unsupportedByEngine) {
        if (check.critical) {
          addBlocker(check.reason);
        } else {
          addWarning(check.reason);
        }
      }
    }

    // 能力判断
    final supportsSearch =
        searchUrlCheck.supported && searchBookListCheck.supported;

    final supportsExplore = exploreUrl.trim().isNotEmpty &&
        exploreUrlCheck.supported &&
        exploreBookListCheck.supported;

    final hasAnyBookUrlRule = _toStr(ruleSearch['bookUrl']).isNotEmpty ||
        _toStr(ruleExplore['bookUrl']).isNotEmpty;

    final hasBookInfoRule = ruleBookInfo.isNotEmpty;

    final supportsDetail = hasBookInfoRule &&
        detailInitCheck.supported &&
        searchBookUrlCheck.supported &&
        exploreBookUrlCheck.supported;

    final supportsToc = chapterListCheck.supported &&
        chapterUrlCheck.supported &&
        tocUrlCheck.supported;

    final supportsContent = contentCheck.supported;

    // 缺字段类 warning，不作为“引擎不支持 blocker”
    if (searchUrl.trim().isEmpty) {
      addWarning('未配置 searchUrl：该源不支持搜索。');
    }
    if (_toStr(ruleSearch['bookList']).trim().isEmpty) {
      addWarning('未配置 ruleSearch.bookList：搜索结果无法提取。');
    }

    if (exploreUrl.trim().isEmpty) {
      addWarning('未配置 exploreUrl：该源不支持发现页。');
    } else {
      if (!exploreUrlCheck.supported &&
          !exploreUrlCheck.unsupportedByEngine &&
          exploreUrlCheck.reason.isNotEmpty) {
        addWarning(exploreUrlCheck.reason);
      }
      if (exploreUrlCheck.supported &&
          !exploreBookListCheck.supported &&
          !exploreBookListCheck.unsupportedByEngine) {
        addWarning('发现页已配置，但缺少可用的 bookList 提取规则。');
      }
    }

    if (!hasBookInfoRule && !hasAnyBookUrlRule) {
      addWarning('未检测到详情相关规则：可能无法进入详情页。');
    }

    if (_toStr(ruleToc['chapterList']).trim().isEmpty) {
      addWarning('未配置 ruleToc.chapterList：目录列表无法提取。');
    }
    if (_toStr(ruleToc['chapterUrl']).trim().isEmpty) {
      addWarning('未配置 ruleToc.chapterUrl：无法定位章节正文。');
    }
    if (_toStr(ruleContent['content']).trim().isEmpty) {
      addWarning('未配置 ruleContent.content：无法提取正文内容。');
    }

    // 特征提示
    if (featureFlags['hasJsBlock'] == true) {
      addWarning('检测到 <js> 脚本块：这类规则通常超出当前通用引擎支持范围。');
    }

    if (featureFlags['hasJavaAjax'] == true) {
      addWarning('检测到 java.ajax 动态请求：通常需要专用适配器。');
    }

    if (featureFlags['hasJavaMd5'] == true) {
      addWarning('检测到 java.md5Encode 签名逻辑：通常需要专用适配器。');
    }

    if (featureFlags['hasJavaPut'] == true ||
        featureFlags['hasJavaGet'] == true ||
        featureFlags['hasAtPut'] == true) {
      addWarning('检测到上下文变量存取规则：当前通用 Rule 仅有限支持。');
    }

    if (_looksLikeExploreMenu(exploreUrl) && ruleExplore.isEmpty) {
      addWarning('发现页未单独配置 ruleExplore：当前会回退使用 ruleSearch 解析。');
    }

    final adapterKind = blockers.isEmpty
        ? NovelSourceAdapterKind.rule
        : NovelSourceAdapterKind.unsupported;

    final adapterLabel = switch (adapterKind) {
      NovelSourceAdapterKind.rule => '通用 Rule 适配器',
      NovelSourceAdapterKind.wtzw => 'WTZW 专用适配器',
      NovelSourceAdapterKind.unsupported => '当前暂不支持',
    };

    return NovelSourceCapabilityReport(
      sourceName: sourceName,
      baseUrl: baseUrl,
      adapterKind: adapterKind,
      adapterLabel: adapterLabel,
      supportsSearch: supportsSearch,
      supportsExplore: supportsExplore,
      supportsDetail: supportsDetail,
      supportsToc: supportsToc,
      supportsContent: supportsContent,
      featureFlags: featureFlags,
      matchedSignals: matchedSignals,
      warnings: warnings,
      blockers: blockers,
    );
  }

  static bool _looksLikeWtzwSource(Map<String, dynamic> json) {
    final baseUrl = _toStr(json['bookSourceUrl']).toLowerCase();
    final searchUrl = _toStr(json['searchUrl']);
    final exploreUrl = _toStr(json['exploreUrl']);
    final ruleContent = _asMap(json['ruleContent']);
    final contentRule = _toStr(ruleContent['content']);

    return baseUrl.contains('wtzw.com') ||
        searchUrl.contains('/api/v5/search/words') ||
        exploreUrl.contains('api-bc.wtzw.com') ||
        contentRule.contains('242ccb8230d709e1') ||
        _containsDeep(json, 'api-ks.wtzw.com');
  }

  static _FieldCheckResult _checkExploreUrlField(String raw) {
    final text = raw.trim();

    if (text.isEmpty) {
      return const _FieldCheckResult(
        field: 'exploreUrl',
        supported: false,
        critical: false,
        reason: '',
        unsupportedByEngine: false,
      );
    }

    if (_looksLikeExploreMenu(text)) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is! List) {
          return const _FieldCheckResult(
            field: 'exploreUrl',
            supported: false,
            critical: false,
            reason: 'exploreUrl 发现菜单格式无效。',
            unsupportedByEngine: false,
          );
        }

        var hasAnyUsableUrl = false;
        for (final item in decoded) {
          if (item is! Map) continue;
          final url = _toStr(item['url']);
          if (url.isEmpty) continue;

          hasAnyUsableUrl = true;
          if (_containsUnsupportedEnginePattern(url)) {
            return const _FieldCheckResult(
              field: 'exploreUrl',
              supported: false,
              critical: false,
              reason: 'exploreUrl 菜单中的 url 使用高级 JS / 上下文规则，当前通用引擎暂不支持。',
              unsupportedByEngine: true,
            );
          }
        }

        if (!hasAnyUsableUrl) {
          return const _FieldCheckResult(
            field: 'exploreUrl',
            supported: false,
            critical: false,
            reason: 'exploreUrl 菜单中没有可用的 url。',
            unsupportedByEngine: false,
          );
        }

        return const _FieldCheckResult(
          field: 'exploreUrl',
          supported: true,
          critical: false,
          reason: '',
          unsupportedByEngine: false,
        );
      } catch (_) {
        return const _FieldCheckResult(
          field: 'exploreUrl',
          supported: false,
          critical: false,
          reason: 'exploreUrl 菜单 JSON 解析失败。',
          unsupportedByEngine: false,
        );
      }
    }

    return _checkField(
      'exploreUrl',
      text,
      critical: false,
    );
  }

  static _FieldCheckResult _checkField(
    String field,
    String value, {
    required bool critical,
    bool allowEmpty = false,
  }) {
    final text = value.trim();

    if (text.isEmpty) {
      return _FieldCheckResult(
        field: field,
        supported: allowEmpty,
        critical: critical,
        reason: allowEmpty ? '' : '$field 为空。',
        unsupportedByEngine: false,
      );
    }

    if (_containsUnsupportedEnginePattern(text)) {
      return _FieldCheckResult(
        field: field,
        supported: false,
        critical: critical,
        reason: '$field 使用高级 JS / 上下文规则，当前通用引擎暂不支持。',
        unsupportedByEngine: true,
      );
    }

    return _FieldCheckResult(
      field: field,
      supported: true,
      critical: critical,
      reason: '',
      unsupportedByEngine: false,
    );
  }

  static bool _containsUnsupportedEnginePattern(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return false;

    if (_isSupportedSpecialJs(text)) {
      return false;
    }

    if (text.contains('<js>') || text.contains('</js>')) return true;
    if (text.contains('java.ajax(')) return true;
    if (text.contains('java.md5Encode(')) return true;
    if (text.contains('java.put(')) return true;
    if (text.contains('java.get(')) return true;
    if (text.contains('@put:{')) return true;

    // 通用 @js: 除了我们已经特判支持的 AES 形式，其它都视为高级脚本
    if (text.contains('@js:')) return true;

    return false;
  }

  static bool _isSupportedSpecialJs(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return false;

    final hasAesDecode =
        text.contains('java.aesBase64DecodeToString(') ||
            text.contains('AES/CBC/PKCS5Padding');

    final hasAdvancedApis = text.contains('java.ajax(') ||
        text.contains('java.md5Encode(') ||
        text.contains('java.put(') ||
        text.contains('java.get(') ||
        text.contains('@put:{') ||
        text.contains('<js>') ||
        text.contains('</js>');

    return hasAesDecode && !hasAdvancedApis;
  }

  static bool _looksLikeExploreMenu(String raw) {
    final text = raw.trim();
    if (!text.startsWith('[') || !text.endsWith(']')) {
      return false;
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return false;

      for (final item in decoded) {
        if (item is Map &&
            (item.containsKey('title') || item.containsKey('url'))) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static bool _containsDeep(dynamic value, String pattern) {
    if (pattern.isEmpty) return false;

    if (value is String) {
      return value.contains(pattern);
    }

    if (value is Map) {
      for (final entry in value.entries) {
        if (_containsDeep(entry.key.toString(), pattern)) return true;
        if (_containsDeep(entry.value, pattern)) return true;
      }
      return false;
    }

    if (value is Iterable) {
      for (final item in value) {
        if (_containsDeep(item, pattern)) return true;
      }
      return false;
    }

    return value?.toString().contains(pattern) ?? false;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static String _toStr(dynamic value) {
    return value == null ? '' : value.toString().trim();
  }
}

class _FieldCheckResult {
  const _FieldCheckResult({
    required this.field,
    required this.supported,
    required this.critical,
    required this.reason,
    required this.unsupportedByEngine,
  });

  final String field;
  final bool supported;
  final bool critical;
  final String reason;
  final bool unsupportedByEngine;
}
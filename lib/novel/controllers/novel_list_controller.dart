import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../core/rule_novel_source.dart';
import '../novel_module.dart';
import '../core/wtzw_novel_source.dart';
class _ExploreEntry {
  final String title;
  final String url;

  const _ExploreEntry({
    required this.title,
    required this.url,
  });
}

class NovelListController extends ChangeNotifier {
  NovelListController() {
    Future.microtask(() => reload());
  }

  final List<NovelBook> _books = <NovelBook>[];
  bool _loading = false;
  bool _loadingMore = false;
  bool _searchMode = false;
  bool _hasMore = true;
  String _keyword = '';
  String _error = '';
  int _page = 1;

  List<NovelBook> get books => List.unmodifiable(_books);
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get searchMode => _searchMode;
  bool get hasMore => _hasMore;
  String get keyword => _keyword;
  String get error => _error;

  bool get isConfigured => NovelModule.isConfigured;
Object? get _activeSource {
  if (!NovelModule.isConfigured) return null;
  return NovelModule.repository.source;
}

String _sourceNameOf(Object? source) {
  if (source is RuleNovelSource) return source.name;
  if (source is WtzwNovelSource) return source.name;
  return '';
}

String _exploreUrlOf(Object? source) {
  if (source is RuleNovelSource) return source.exploreUrl;
  if (source is WtzwNovelSource) return source.exploreUrl;
  return '';
}

  bool get supportsExplore => _resolvePrimaryExploreEntry(page: 1) != null;

  Future<void> reload({bool forceRefresh = false}) async {
    if (!isConfigured) {
      _books.clear();
      _error = '';
      _loading = false;
      _loadingMore = false;
      _hasMore = false;
      notifyListeners();
      return;
    }

    if (_searchMode && _keyword.trim().isNotEmpty) {
      await _loadSearchPage(1, reset: true);
      return;
    }

    if (!supportsExplore) {
      _books.clear();
      _error = '';
      _page = 1;
      _hasMore = false;
      notifyListeners();
      return;
    }

    await _loadExplorePage(1, reset: true);
  }

  Future<void> search(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return;

    _keyword = kw;
    _searchMode = true;
    await _loadSearchPage(1, reset: true);
  }

  Future<void> cancelSearch() async {
    _keyword = '';
    _searchMode = false;
    await reload();
  }

  Future<void> loadMore() async {
    if (!isConfigured) return;
    if (_loading || _loadingMore || !_hasMore) return;

    if (_searchMode) {
      if (_keyword.trim().isEmpty) return;
      await _loadSearchPage(_page + 1, reset: false);
      return;
    }

    if (!supportsExplore) return;
    await _loadExplorePage(_page + 1, reset: false);
  }

  Future<void> _loadSearchPage(
    int page, {
    required bool reset,
  }) async {
    if (!isConfigured) return;

    if (reset) {
      _loading = true;
      _loadingMore = false;
      _error = '';
      notifyListeners();
    } else {
      _loadingMore = true;
      _error = '';
      notifyListeners();
    }

    try {
      final result = await NovelModule.repository.source.searchBooks(
        _keyword,
        page: page,
      );

      if (reset) {
        _books
          ..clear()
          ..addAll(result);
      } else {
        _books.addAll(result);
      }

      _page = page;
      _hasMore = result.isNotEmpty;
    } catch (e) {
      _error = '加载失败：$e';
      if (reset) {
        _books.clear();
      }
      _hasMore = false;
    } finally {
      _loading = false;
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> _loadExplorePage(
    int page, {
    required bool reset,
  }) async {
    if (!isConfigured) return;

    final entry = _resolvePrimaryExploreEntry(page: page);
    if (entry == null || entry.url.trim().isEmpty) {
      if (reset) {
        _books.clear();
      }
      _error = '';
      _hasMore = false;
      notifyListeners();
      return;
    }

    if (reset) {
      _loading = true;
      _loadingMore = false;
      _error = '';
      notifyListeners();
    } else {
      _loadingMore = true;
      _error = '';
      notifyListeners();
    }

    try {
      final result = await NovelModule.repository.source.fetchByPath(entry.url);

      if (reset) {
        _books
          ..clear()
          ..addAll(result);
      } else {
        _books.addAll(result);
      }

      _page = page;
      _hasMore = result.isNotEmpty;
    } catch (e) {
      _error = '加载失败：$e';
      if (reset) {
        _books.clear();
      }
      _hasMore = false;
    } finally {
      _loading = false;
      _loadingMore = false;
      notifyListeners();
    }
  }

  _ExploreEntry? _resolvePrimaryExploreEntry({
    required int page,
  }) {
    final source = _ruleSource;
    if (source == null) return null;

    final raw = source.exploreUrl.trim();
    if (raw.isEmpty) return null;

    // 情况 1：普通字符串 URL
    if (!raw.startsWith('[')) {
      final url = _renderExploreUrl(raw, page);
      if (url.isEmpty) return null;
      return _ExploreEntry(title: '发现', url: url);
    }

    // 情况 2：阅读风格 discover 数组
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is! Map) continue;

          final map = Map<String, dynamic>.from(item);
          final title = '${map['title'] ?? ''}'.trim();
          final urlTemplate = '${map['url'] ?? ''}'.trim();

          // 跳过分组标题 / 空 url
          if (urlTemplate.isEmpty) continue;

          final url = _renderExploreUrl(urlTemplate, page);
          if (url.isEmpty) continue;

          return _ExploreEntry(
            title: title.isNotEmpty ? title : '发现',
            url: url,
          );
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  String _renderExploreUrl(String template, int page) {
    return template
        .trim()
        .replaceAll('{{page}}', '$page')
        .replaceAll('{page}', '$page');
  }
}
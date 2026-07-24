import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/app_tokens.dart';
import '../../design_system/widgets/shimmer_skeleton.dart';
import '../../design_system/widgets/empty_error_states.dart';
import '../../../design_system/widgets/app_page_scaffold.dart';
import '../core/book_deduplicator.dart';
import '../core/models.dart';
import '../core/rule_novel_source.dart';
import '../novel_module.dart';
import '../core/wtzw_novel_source.dart';
import 'widgets/novel_book_card.dart';
import 'widgets/novel_list_views.dart';
import 'widgets/novel_list_bars.dart';
import 'widgets/novel_stats_bar.dart';
import 'widgets/novel_cache_dialog.dart';
import '../core/novel_cache_manager.dart';

/// 包装类，兼容原有 `NovelListPageWithProvider()` 入口写法。
class NovelListPageWithProvider extends StatelessWidget {
  const NovelListPageWithProvider({super.key});

  @override
  Widget build(BuildContext context) {
    return const NovelListPage();
  }
}

class _ExploreMenuEntry extends ExploreMenuEntry {
  const _ExploreMenuEntry({required super.title, required super.url});
}

class NovelListPage extends StatefulWidget {
  const NovelListPage({super.key});

  @override
  State<NovelListPage> createState() => _NovelListPageState();
}

class _NovelListPageState extends State<NovelListPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _bootstrapping = true;
  bool _configured = false;

  bool _loading = false;
  bool _loadingMore = false;
  bool _searchMode = false;
  bool _hasMore = true;

  int _page = 1;
  int _selectedExploreIndex = 0;

  String _keyword = '';
  String _error = '';
  String _startupMessage = '';
  String _currentSourceName = '';

  final List<NovelBook> _books = <NovelBook>[];
  List<_ExploreMenuEntry> _exploreEntries = const [];
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

  bool get _supportsExplore => _exploreEntries.isNotEmpty;

  // ── 缓存管理 ──
  late final NovelCacheManager _cacheManager;

  Future<void> _showCacheDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => NovelCacheDialog(cacheManager: _cacheManager),
    );
    // 重新加载页面以更新缓存统计
    if (mounted) setState(() {});
  }

  _ExploreMenuEntry? get _selectedExploreEntry {
    if (_selectedExploreIndex < 0 ||
        _selectedExploreIndex >= _exploreEntries.length) {
      return null;
    }
    return _exploreEntries[_selectedExploreIndex];
  }

  @override
  void initState() {
    super.initState();
    _cacheManager = NovelCacheManager(namespace: 'novel');
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapAndLoad();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels > position.maxScrollExtent - 260) {
      _loadMore();
    }
  }

  Future<void> _bootstrapAndLoad({bool preserveExploreIndex = true}) async {
    setState(() {
      _bootstrapping = true;
      _error = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final result = await BookSourceBootstrap.loadAndConfigure(prefs);

      final configured = result.configured || NovelModule.isConfigured;
      if (!mounted) return;

      if (!configured) {
        setState(() {
          _bootstrapping = false;
          _configured = false;
          _startupMessage = result.message;
          _currentSourceName = '';
          _exploreEntries = const [];
          _selectedExploreIndex = 0;
          _books.clear();
          _hasMore = false;
          _loading = false;
          _loadingMore = false;
        });
        return;
      }
      final activeSource = _activeSource;
      final sourceName = _sourceNameOf(activeSource).trim().isNotEmpty
          ? _sourceNameOf(activeSource).trim()
          : (result.source?.bookSourceName ?? '当前书源');

      final rawExploreUrl = _exploreUrlOf(activeSource);
      final entries = rawExploreUrl.trim().isNotEmpty
          ? _parseExploreEntries(rawExploreUrl)
          : const <_ExploreMenuEntry>[];

      int nextSelectedIndex = 0;
      if (preserveExploreIndex &&
          _selectedExploreIndex >= 0 &&
          _selectedExploreIndex < entries.length) {
        nextSelectedIndex = _selectedExploreIndex;
      }

      setState(() {
        _bootstrapping = false;
        _configured = true;
        _startupMessage = result.message;
        _currentSourceName = sourceName;
        _exploreEntries = entries;
        _selectedExploreIndex = nextSelectedIndex;
      });

      if (_searchMode && _keyword.trim().isNotEmpty) {
        await _loadSearchPage(1, reset: true);
        return;
      }

      if (_supportsExplore) {
        await _loadExplorePage(1, reset: true);
      } else {
        setState(() {
          _books.clear();
          _page = 1;
          _hasMore = false;
          _error = '';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootstrapping = false;
        _configured = false;
        _startupMessage = '初始化书源失败：$e';
        _books.clear();
        _hasMore = false;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  List<_ExploreMenuEntry> _parseExploreEntries(String rawExplore) {
    final raw = rawExplore.trim();
    if (raw.isEmpty) return const <_ExploreMenuEntry>[];

    // 普通单 URL 模式
    if (!raw.startsWith('[')) {
      return [_ExploreMenuEntry(title: '发现', url: raw)];
    }

    // 阅读风格数组 discover 模式
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <_ExploreMenuEntry>[];

      final out = <_ExploreMenuEntry>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final title = '${map['title'] ?? ''}'.trim();
        final url = '${map['url'] ?? ''}'.trim();

        // 跳过纯分组标题和空链接
        if (url.isEmpty) continue;

        out.add(
          _ExploreMenuEntry(title: title.isNotEmpty ? title : '发现', url: url),
        );
      }

      return out;
    } catch (_) {
      return const <_ExploreMenuEntry>[];
    }
  }

  String _renderPageTemplate(String template, int page) {
    return template
        .trim()
        .replaceAll('{{page}}', '$page')
        .replaceAll('{page}', '$page');
  }

  String _currentExplorePath(int page) {
    final entry = _selectedExploreEntry;
    if (entry == null) return '';
    return _renderPageTemplate(entry.url, page);
  }

  Future<void> _doSearch() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    _keyword = keyword;
    _searchMode = true;
    await _loadSearchPage(1, reset: true);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
  }

  Future<void> _cancelSearch() async {
    _searchController.clear();
    _keyword = '';
    _searchMode = false;

    if (_supportsExplore) {
      await _loadExplorePage(1, reset: true);
    } else {
      setState(() {
        _books.clear();
        _error = '';
        _page = 1;
        _hasMore = false;
      });
    }
  }

  Future<void> _selectExplore(int index) async {
    if (index < 0 || index >= _exploreEntries.length) return;
    if (_selectedExploreIndex == index && !_searchMode) return;

    setState(() {
      _selectedExploreIndex = index;
      _searchMode = false;
      _keyword = '';
    });

    await _loadExplorePage(1, reset: true);
  }

  Future<void> _loadMore() async {
    if (!_configured) return;
    if (_loading || _loadingMore || !_hasMore) return;

    if (_searchMode) {
      if (_keyword.trim().isEmpty) return;
      await _loadSearchPage(_page + 1, reset: false);
      return;
    }

    if (!_supportsExplore) return;
    await _loadExplorePage(_page + 1, reset: false);
  }

  Future<void> _loadSearchPage(int page, {required bool reset}) async {
    if (!_configured || !NovelModule.isConfigured) return;

    setState(() {
      if (reset) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
      _error = '';
    });

    try {
      final result = await NovelModule.repository.source.searchBooks(
        _keyword,
        page: page,
      );

      if (!mounted) return;

      setState(() {
        if (reset) {
          _books
            ..clear()
            ..addAll(result);
        } else {
          _appendUniqueBooks(result);
        }
        _page = page;
        _hasMore = result.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
        if (reset) {
          _books.clear();
        }
        _hasMore = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadExplorePage(int page, {required bool reset}) async {
    if (!_configured || !NovelModule.isConfigured) return;

    final path = _currentExplorePath(page);
    if (path.trim().isEmpty) {
      setState(() {
        if (reset) {
          _books.clear();
        }
        _error = '';
        _hasMore = false;
        _loading = false;
        _loadingMore = false;
      });
      return;
    }

    setState(() {
      if (reset) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
      _error = '';
    });

    try {
      final result = await NovelModule.repository.source.fetchByPath(path);

      if (!mounted) return;

      setState(() {
        if (reset) {
          _books
            ..clear()
            ..addAll(result);
        } else {
          _appendUniqueBooks(result);
        }
        _page = page;
        _hasMore = result.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
        if (reset) {
          _books.clear();
        }
        _hasMore = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _appendUniqueBooks(List<NovelBook> incoming) {
    BookDeduplicator.appendUnique(_books, incoming);
  }

  Future<void> _openSourceManager() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookSourceManagerPage(startupMessage: _startupMessage),
      ),
    );

    if (!mounted) return;
    await _bootstrapAndLoad();
  }

  Widget _buildCompactHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: _openSourceManager,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTokens.violet.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.library_books_rounded,
                    size: 14,
                    color: AppTokens.violet,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _currentSourceName.isNotEmpty ? _currentSourceName : '书源',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.violet,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (_searchMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '搜索：$_keyword',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue,
                ),
              ),
            ),
          if (_supportsExplore && !_searchMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTokens.emerald.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '发现 · ${_books.length}本',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.emerald,
                ),
              ),
            ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _loading ? null : _handleRefresh,
            style: IconButton.styleFrom(
              foregroundColor: AppTokens.textSecondary,
              padding: const EdgeInsets.all(6),
              minimumSize: const Size(32, 32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return NovelSearchBar(
      controller: _searchController,
      onSearch: _doSearch,
      onCancel: _cancelSearch,
      showCancel: _searchMode,
    );
  }

  Widget _buildExploreBar() {
    if (_searchMode || !_supportsExplore || _exploreEntries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
      child: SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemBuilder: (context, index) {
            final entry = _exploreEntries[index];
            final isSelected = index == _selectedExploreIndex;
            return GestureDetector(
              onTap: () => _selectExplore(index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isSelected ? AppTokens.violet : AppTokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppTokens.violet : AppTokens.divider,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  entry.title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppTokens.textSecondary,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            );
          },
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemCount: _exploreEntries.length,
        ),
      ),
    );
  }

  Widget _buildNotConfiguredView() {
    return NovelNotConfiguredView(
      message: _startupMessage,
      onConfigurePressed: _openSourceManager,
    );
  }

  Widget _buildLoadingView() {
    return const BookListSkeleton();
  }

  Widget _buildEmptyView() {
    final text = _searchMode
        ? (_error.isNotEmpty ? _error : '没有搜索到相关书籍')
        : _supportsExplore
        ? (_error.isNotEmpty ? _error : '暂无相关数据')
        : '当前书源不支持发现页，请直接搜索';
    if (_error.isNotEmpty) {
      return ErrorStateView(
        message: text,
        onRetry: _searchMode
            ? () => _doSearch()
            : null,
      );
    }
    return EmptyStateView(
      icon: _searchMode ? Icons.search_off_rounded : Icons.explore_off_rounded,
      title: text,
      subtitle: _searchMode ? '试试换个关键词搜索' : '试试切换其他书源',
    );
  }

  Widget _buildListBody() {
    if (_bootstrapping) {
      return _buildLoadingView();
    }

    if (!_configured) {
      return _buildNotConfiguredView();
    }

    if (_loading && _books.isEmpty) {
      return _buildLoadingView();
    }

    if (_books.isEmpty) {
      return _buildEmptyView();
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        16,
        8,
        16,
        AppTokens.pageBottomPadding + 32,
      ),
      itemCount: _books.length + 1,
      itemBuilder: (context, index) {
        if (index < _books.length) {
          return NovelBookCard(book: _books[index]);
        }

        if (_loadingMore) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        if (!_hasMore) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text('到底了', style: TextStyle(color: Colors.black45)),
            ),
          );
        }

        return const SizedBox(height: 8);
      },
    );
  }

  Future<void> _handleRefresh() async {
    if (_bootstrapping) return;
    if (!_configured) {
      await _bootstrapAndLoad();
      return;
    }

    if (_searchMode) {
      await _loadSearchPage(1, reset: true);
      return;
    }

    if (_supportsExplore) {
      await _loadExplorePage(1, reset: true);
      return;
    }

    setState(() {
      _books.clear();
      _error = '';
      _page = 1;
      _hasMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      maxContentWidth: 660,
      safeBottom: false,
      child: Column(
        children: [
          _buildCompactHeader(),
          NovelStatsBar(
            sourceCount: _currentSourceName.isNotEmpty ? 1 : 0,
            bookCount: _books.length,
            cacheManager: _cacheManager,
            onCacheTapped: _showCacheDialog,
          ),
          _buildSearchBar(),
          _buildExploreBar(),
          if (_error.isNotEmpty && _books.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _handleRefresh,
              child: _buildListBody(),
            ),
          ),
        ],
      ),
    );
  }
}

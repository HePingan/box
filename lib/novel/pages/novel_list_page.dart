import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/app_tokens.dart';
import '../../../design_system/widgets/app_cards.dart';
import '../../../design_system/widgets/app_page_scaffold.dart';
import '../controllers/novel_detail_controller.dart';
import '../core/models.dart';
import '../core/rule_novel_source.dart';
import '../novel_module.dart';
import 'novel_detail_page.dart';
import 'source_manager/book_source_bootstrap.dart';
import 'source_manager/book_source_manager_page.dart';
import '../core/wtzw_novel_source.dart';

/// 为了兼容你项目里之前所有入口仍然使用
/// `NovelListPageWithProvider()` 的写法，这里保留这个包装类。
/// 但增强版页面本身已经不依赖 NovelListController 了。
class NovelListPageWithProvider extends StatelessWidget {
  const NovelListPageWithProvider({super.key});

  @override
  Widget build(BuildContext context) {
    return const NovelListPage();
  }
}

class _ExploreMenuEntry {
  final String title;
  final String url;

  const _ExploreMenuEntry({required this.title, required this.url});
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
    final seen = <String>{
      for (final b in _books)
        b.id.isNotEmpty ? 'id:${b.id}' : 'url:${b.detailUrl}',
    };

    for (final b in incoming) {
      final key = b.id.isNotEmpty ? 'id:${b.id}' : 'url:${b.detailUrl}';
      if (seen.add(key)) {
        _books.add(b);
      }
    }
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

  Widget _buildCoverFallback({double width = 64, double height = 86}) {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF312E81), Color(0xFF7C3AED), Color(0xFFF59E0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.auto_stories_rounded, color: Colors.white70),
    );
  }

  Widget _buildBookCard(NovelBook book) {
    final meta = <String>[
      if (book.author.trim().isNotEmpty) '作者 ${book.author.trim()}',
      if (book.category.trim().isNotEmpty) book.category.trim(),
      if (book.status.trim().isNotEmpty) book.status.trim(),
      if (book.wordCount.trim().isNotEmpty) book.wordCount.trim(),
    ].join(' · ');

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider(
              create: (_) => NovelDetailController(entryBook: book),
              child: NovelDetailPage(entryBook: book),
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFEDE9FE)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: book.coverUrl.trim().isNotEmpty
                  ? Image.network(
                      book.coverUrl,
                      width: 76,
                      height: 108,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _buildCoverFallback(width: 76, height: 108),
                    )
                  : _buildCoverFallback(width: 76, height: 108),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: SizedBox(
                height: 108,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title.trim().isNotEmpty ? book.title : '未知书名',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      meta.isNotEmpty ? meta : '作者与分类待补全',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7C3AED),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      book.intro.trim().isNotEmpty
                          ? book.intro
                          : '还没有简介哦，点击进入查看章节。',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    return AppLightHeroCard(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      eyebrow: '阅读内容中心',
      title: '小说书架',
      subtitle: _currentSourceName.isNotEmpty
          ? '当前书源：$_currentSourceName · 搜索与发现'
          : '导入书源后即可搜索与发现新书',
      badge: 'NOVEL',
      accentGradient: AppTokens.violetGradient,
      leading: _NovelLightIconButton(
        icon: Icons.local_library_rounded,
        onTap: _openSourceManager,
      ),
      actions: [
        AppStatusPill(
          label: '书源管理',
          icon: Icons.tune_rounded,
          color: AppTokens.violet,
        ),
        AppStatusPill(
          label: _loading ? '加载中' : '刷新',
          icon: _loading ? Icons.sync_rounded : Icons.refresh_rounded,
          color: AppTokens.primaryBlue,
        ),
      ],
      metrics: [
        Expanded(
          child: _NovelLightMetric(
            value: '${_books.length}',
            label: _searchMode ? '搜索结果' : '发现书籍',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _NovelLightMetric(
            value: '${_exploreEntries.length}',
            label: '发现频道',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _NovelLightMetric(
            value: _supportsExplore ? '发现' : '搜索',
            label: '当前模式',
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _doSearch(),
              decoration: InputDecoration(
                hintText: '输入书名或作者名进行搜索',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchMode
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _cancelSearch,
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade50,
              foregroundColor: Colors.blue.shade700,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _doSearch,
            child: const Text('搜索'),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceInfo() {
    final activeExploreTitle = _selectedExploreEntry?.title ?? '';

    final subtitle = _searchMode
        ? '搜索结果：${_keyword.isNotEmpty ? _keyword : "未命名关键词"}'
        : _supportsExplore
        ? '当前显示：${activeExploreTitle.isNotEmpty ? activeExploreTitle : "书源发现页"}'
        : '当前书源不支持发现页，请直接搜索';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_currentSourceName.isNotEmpty)
            Text(
              '书源：$_currentSourceName',
              style: const TextStyle(
                fontSize: 12.5,
                color: Colors.blueGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildExploreBar() {
    if (_searchMode || !_supportsExplore) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 46,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final item = _exploreEntries[index];
          final selected = index == _selectedExploreIndex;

          return ChoiceChip(
            label: Text(item.title),
            selected: selected,
            onSelected: (_) => _selectExplore(index),
            selectedColor: Colors.blue.shade50,
            labelStyle: TextStyle(
              color: selected ? Colors.blue.shade700 : Colors.black87,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            side: BorderSide(
              color: selected ? Colors.blue.shade200 : Colors.grey.shade300,
            ),
            backgroundColor: Colors.white,
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemCount: _exploreEntries.length,
      ),
    );
  }

  Widget _buildNotConfiguredView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        24,
        40,
        24,
        AppTokens.pageBottomPadding + 32,
      ),
      children: [
        const SizedBox(height: 80),
        const Icon(
          Icons.auto_stories_outlined,
          size: 60,
          color: Colors.black26,
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            '未配置规则书源',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.redAccent,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            _startupMessage.isNotEmpty ? _startupMessage : '请先导入并启用一个小说书源。',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: ElevatedButton.icon(
            onPressed: _openSourceManager,
            icon: const Icon(Icons.tune),
            label: const Text('去配置书源'),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 180),
        Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _buildEmptyView() {
    String text;

    if (_searchMode) {
      text = _error.isNotEmpty ? _error : '没有搜索到相关书籍';
    } else if (_supportsExplore) {
      text = _error.isNotEmpty ? _error : '暂无相关数据';
    } else {
      text = '当前书源不支持发现页，请直接搜索';
    }

    final errorStyle = TextStyle(
      color: _error.isNotEmpty ? Colors.redAccent : Colors.black54,
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 180),
        Center(child: Text(text, style: errorStyle)),
        const SizedBox(height: AppTokens.pageBottomPadding + 32),
      ],
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
          return _buildBookCard(_books[index]);
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
      safeBottom: false,
      child: Column(
        children: [
          _buildHeroSection(),
          _buildSearchBar(),
          _buildSourceInfo(),
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

class _NovelLightIconButton extends StatelessWidget {
  const _NovelLightIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E8F6)),
        ),
        child: Icon(icon, color: AppTokens.violet, size: 21),
      ),
    );
  }
}

class _NovelLightMetric extends StatelessWidget {
  const _NovelLightMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FD),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

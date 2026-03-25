import 'package:flutter/material.dart';

import '../core/discover_routes.dart';
import '../core/models.dart';
import '../novel_module.dart';
import 'novel_detail_page.dart';

enum SearchTarget { all, title, author }

class NovelListPage extends StatefulWidget {
  const NovelListPage({super.key});

  @override
  State<NovelListPage> createState() => _NovelListPageState();
}

class _NovelListPageState extends State<NovelListPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  NovelChannel _channel = NovelChannel.male;
  late List<DiscoverGroup> _groups;
  int _groupIndex = 0;
  DiscoverRoute? _selectedRoute;

  bool _searchMode = false;
  String _searchKeyword = '';
  
  // 💡 新增的模式控制状态
  SearchTarget _searchTarget = SearchTarget.all;

  int _page = 1;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String _error = '';

  final List<NovelBook> _books = [];

  @override
  void initState() {
    super.initState();
    _groups = QmDiscoverCatalog.groupsOf(_channel);
    _selectedRoute = QmDiscoverCatalog.defaultRouteOf(_channel);
    _scrollController.addListener(_onScroll);
    _reload(forceRefresh: false);
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
    final pos = _scrollController.position;
    if (pos.pixels > pos.maxScrollExtent - 260) {
      _loadMore();
    }
  }

  String _bookKey(NovelBook b) {
    if (b.detailUrl.isNotEmpty) return b.detailUrl;
    if (b.id.isNotEmpty) return b.id;
    return '${b.title}_${b.author}';
  }

  List<NovelBook> _mergeBooks(List<NovelBook> oldList, List<NovelBook> nextList) {
    final seen = <String>{};
    final result = <NovelBook>[];
    for (final b in [...oldList, ...nextList]) {
      final key = _bookKey(b);
      if (key.isNotEmpty && seen.add(key)) result.add(b);
    }
    return result;
  }

  Future<List<NovelBook>> _fetchPage(int page, {required bool forceRefresh}) async {
    if (_searchMode) {
      final keyword = _searchKeyword.trim();
      return await NovelModule.repository.searchBooks(
        keyword, 
        page: page, 
        forceRefresh: forceRefresh
      );
    }

    final route = _selectedRoute;
    if (route == null) return const <NovelBook>[];
    return NovelModule.repository.fetchByPath(
      route.buildPath(page),
      forceRefresh: forceRefresh,
    );
  }

  Future<void> _reload({required bool forceRefresh}) async {
    setState(() {
      _page = 1;
      _loading = true;
      _loadingMore = false;
      _hasMore = true;
      _error = '';
    });

    try {
      final books = await _fetchPage(1, forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _books
          ..clear()
          ..addAll(books);
        _hasMore = books.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载失败：$e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;

    setState(() {
      _loadingMore = true;
      _error = '';
    });

    final nextPage = _page + 1;
    try {
      final books = await _fetchPage(nextPage, forceRefresh: false);
      if (!mounted) return;

      final before = _books.length;
      final merged = _mergeBooks(_books, books);
      final added = merged.length - before;

      setState(() {
        _books
          ..clear()
          ..addAll(merged);
        
        _page = nextPage;
        _hasMore = books.isNotEmpty && added > 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '没有更多数据了');
    } finally {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _switchChannel(NovelChannel channel) {
    if (_channel == channel) return;
    setState(() {
      _channel = channel;
      _groups = QmDiscoverCatalog.groupsOf(channel);
      _groupIndex = 0;
      _selectedRoute = _groups.first.routes.first;
      _searchMode = false;
      _searchKeyword = '';
      _searchTarget = SearchTarget.all;
    });
    _reload(forceRefresh: false);
  }

  void _selectGroup(int index) {
    if (_groupIndex == index) return;
    setState(() {
      _groupIndex = index;
      _selectedRoute = _groups[index].routes.first;
      _searchMode = false;
      _searchKeyword = '';
      _searchTarget = SearchTarget.all;
    });
    _reload(forceRefresh: false);
  }

  void _selectRoute(DiscoverRoute route) {
    if (_selectedRoute?.key == route.key) return;
    setState(() {
      _selectedRoute = route;
      _searchMode = false;
      _searchKeyword = '';
      _searchTarget = SearchTarget.all;
    });
    _reload(forceRefresh: false);
  }

  void _doSearch() {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;
    setState(() {
      _searchMode = true;
      _searchKeyword = keyword;
    });
    FocusScope.of(context).unfocus(); 
    _reload(forceRefresh: true); 
  }

  void _cancelSearch() {
    if (!_searchMode) return;
    setState(() {
      _searchMode = false;
      _searchKeyword = '';
      _searchController.clear();
      _searchTarget = SearchTarget.all;
    });
    _reload(forceRefresh: false);
  }

  Widget _buildBookCard(NovelBook book) {
    final meta = <String>[
      if (book.author.isNotEmpty) book.author,
      if (book.category.isNotEmpty) book.category,
      if (book.status.isNotEmpty) book.status,
      if (book.wordCount.isNotEmpty) book.wordCount,
    ].join(' · ');

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NovelDetailPage(entryBook: book),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                book.coverUrl,
                width: 64,
                height: 86,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 64,
                  height: 86,
                  color: Colors.grey[200],
                  alignment: Alignment.center,
                  child: const Icon(Icons.menu_book, color: Colors.black38),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 86,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title.isNotEmpty ? book.title : '未知书名',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      meta.isNotEmpty ? meta : '暂无信息',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.intro.isNotEmpty ? book.intro : '还没有简介哦。',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: Colors.black54),
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

  // 💡 重点提纯逻辑：根据你选择的模式实时筛选列表
  List<NovelBook> get _displayBooks {
    if (!_searchMode || _searchTarget == SearchTarget.all) return _books;
    
    // 只保留汉字和字母比对，提高过滤容错率
    String cleanRaw(String s) => s.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]'), '').toLowerCase();
    final cleanKeyword = cleanRaw(_searchKeyword);
    
    return _books.where((b) {
      if (_searchTarget == SearchTarget.title) {
        return cleanRaw(b.title).contains(cleanKeyword);
      } else {
        return cleanRaw(b.author).contains(cleanKeyword);
      }
    }).toList();
  }

  Widget _buildListBody() {
    if (_loading && _books.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 180),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    final displayList = _displayBooks;

    // 💡 处理源站有数据，但过滤后没数据的尴尬情况（防止无法滑动）
    if (displayList.isEmpty && _books.isNotEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          Center(
            child: Text(
              _searchTarget == SearchTarget.title ? '当前页面没有名字为“$_searchKeyword”的书' : '当前页面没找到作者“$_searchKeyword”',
              style: const TextStyle(color: Colors.black54),
            ),
          ),
          const SizedBox(height: 16),
          if (_hasMore)
            Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600]),
                onPressed: _loadingMore ? null : _loadMore,
                icon: _loadingMore 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.arrow_downward, size: 16, color: Colors.white),
                label: Text(_loadingMore ? '正在深网打捞...' : '绕过这页，继续深挖', style: const TextStyle(color: Colors.white)),
              ),
            ),
        ],
      );
    }

    if (_books.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
           const SizedBox(height: 180),
           Center(
            child: Text(
              _error.isNotEmpty ? _error : '暂无相关数据',
              style: TextStyle(
                color: _error.isNotEmpty ? Colors.redAccent : Colors.black54,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: displayList.length + 1,
      itemBuilder: (context, index) {
        if (index < displayList.length) {
          return _buildBookCard(displayList[index]);
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

  @override
  Widget build(BuildContext context) {
    final currentGroup = _groups[_groupIndex];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '小说',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _reload(forceRefresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
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
                    backgroundColor: Colors.blue[50],
                    foregroundColor: Colors.blue[700],
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                  ),
                  onPressed: _doSearch,
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),

          // 💡 前端零延迟过滤条，只在搜索模式下出现！
          if (_searchMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                   const Text('模式：', style: TextStyle(fontSize: 13, color: Colors.black54)),
                   const SizedBox(width: 8),
                   ChoiceChip(
                     label: const Text('综合', style: TextStyle(fontSize: 12)),
                     selected: _searchTarget == SearchTarget.all,
                     showCheckmark: false,
                     onSelected: (_) => setState(() => _searchTarget = SearchTarget.all),
                   ),
                   const SizedBox(width: 8),
                   ChoiceChip(
                     label: const Text('搜书名', style: TextStyle(fontSize: 12)),
                     selected: _searchTarget == SearchTarget.title,
                     showCheckmark: false,
                     onSelected: (_) => setState(() => _searchTarget = SearchTarget.title),
                   ),
                   const SizedBox(width: 8),
                   ChoiceChip(
                     label: const Text('搜作者', style: TextStyle(fontSize: 12)),
                     selected: _searchTarget == SearchTarget.author,
                     showCheckmark: false,
                     onSelected: (_) => setState(() => _searchTarget = SearchTarget.author),
                   ),
                ],
              ),
            ),

          if (!_searchMode) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('男频'),
                    selected: _channel == NovelChannel.male,
                    showCheckmark: false,
                    onSelected: (_) => _switchChannel(NovelChannel.male),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('女频'),
                    selected: _channel == NovelChannel.female,
                    showCheckmark: false,
                    onSelected: (_) => _switchChannel(NovelChannel.female),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 42,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _groups.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final selected = i == _groupIndex;
                  return ChoiceChip(
                    label: Text(_groups[i].title),
                    selected: selected,
                    onSelected: (_) => _selectGroup(i),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 42,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: currentGroup.routes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final route = currentGroup.routes[i];
                  final selected = _selectedRoute?.key == route.key;
                  return ChoiceChip(
                    label: Text(route.title),
                    selected: selected,
                    onSelected: (_) => _selectRoute(route),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
          ],
          
          if (_error.isNotEmpty && _books.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _reload(forceRefresh: true),
              child: _buildListBody(),
            ),
          ),
        ],
      ),
    );
  }
}
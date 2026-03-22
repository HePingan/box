import 'package:flutter/material.dart';

import '../core/discover_routes.dart';
import '../core/models.dart';
import '../novel_module.dart';
import 'novel_detail_page.dart';

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

  String _bookKey(NovelBook b) => '${b.id}|${b.detailUrl}';

  List<NovelBook> _mergeBooks(List<NovelBook> oldList, List<NovelBook> nextList) {
    final keys = oldList.map(_bookKey).toSet();
    final result = List<NovelBook>.from(oldList);
    for (final b in nextList) {
      final k = _bookKey(b);
      if (keys.add(k)) result.add(b);
    }
    return result;
  }

  Future<List<NovelBook>> _fetchPage(int page, {required bool forceRefresh}) async {
    if (_searchMode) {
      List<NovelBook> rawResults = [];

      // 🚀 深海打捞机制：如果用户是搜第 1 页，我们直接并发向服务器讨要前 3 页！
      if (page == 1) {
        try {
          // Future.wait 会同时发出三个请求，速度极快，不增加用户等待时间
          final res = await Future.wait([
            NovelModule.repository.searchBooks(_searchKeyword, page: 1, forceRefresh: forceRefresh),
            NovelModule.repository.searchBooks(_searchKeyword, page: 2, forceRefresh: forceRefresh),
            NovelModule.repository.searchBooks(_searchKeyword, page: 3, forceRefresh: forceRefresh),
          ]);
          
          // 把三页（大概60本书）全部汇聚到一个池子里
          rawResults.addAll(res[0]);
          rawResults.addAll(res[1]);
          rawResults.addAll(res[2]);

          // 去除可能重复的书籍（通过 detailUrl 唯一标识）
          final seen = <String>{};
          rawResults.retainWhere((book) => seen.add(book.detailUrl));
        } catch (e) {
          // 如果某页碰巧网络出错，做个保底：乖乖只拿第1页
          rawResults = await NovelModule.repository.searchBooks(_searchKeyword, page: 1, forceRefresh: forceRefresh);
        }
      } else {
        // 由于我们在第1页已经把服务器的前3页榨干了
        // 所以当用户在手机上滑，需要拉取第 2 页数据时，我们实际跟服务器要第 4 页的数据。
        final serverPage = page + 2; 
        rawResults = await NovelModule.repository.searchBooks(_searchKeyword, page: serverPage, forceRefresh: forceRefresh);
      }

      // 👉 开始在 60 本书中执行降维打击，把作者强行抓到最前面
      final sortedResults = List<NovelBook>.from(rawResults);
      sortedResults.sort((a, b) {
        final keyword = _searchKeyword;
        
        final aExact = a.author == keyword ? 1 : 0;
        final bExact = b.author == keyword ? 1 : 0;
        if (aExact != bExact) return bExact.compareTo(aExact);

        final aContains = a.author.contains(keyword) ? 1 : 0;
        final bContains = b.author.contains(keyword) ? 1 : 0;
        if (aContains != bContains) return bContains.compareTo(aContains);

        return 0; 
      });

      return sortedResults;
    }

    // 默认的分类获取逻辑不变
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
      setState(() {
        _error = '加载失败：$e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
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
      setState(() {
        _error = '加载更多失败：$e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
      });
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
    });
    _reload(forceRefresh: false);
  }

  void _selectRoute(DiscoverRoute route) {
    if (_selectedRoute?.key == route.key) return;
    setState(() {
      _selectedRoute = route;
      _searchMode = false;
      _searchKeyword = '';
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
    _reload(forceRefresh: false);
  }

  void _cancelSearch() {
    if (!_searchMode) return;
    setState(() {
      _searchMode = false;
      _searchKeyword = '';
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
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.intro,
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

    if (_books.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 180),
          Center(
            child: Text(
              _error.isNotEmpty ? _error : '暂无数据',
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
              child: Text('没有更多了', style: TextStyle(color: Colors.black45)),
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
                      hintText: '搜索书名 / 作者',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchMode
                          ? IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: _cancelSearch,
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _doSearch,
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('男频'),
                  selected: _channel == NovelChannel.male,
                  onSelected: (_) => _switchChannel(NovelChannel.male),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('女频'),
                  selected: _channel == NovelChannel.female,
                  onSelected: (_) => _switchChannel(NovelChannel.female),
                ),
                const Spacer(),
                if (_searchMode)
                  Text(
                    '搜索: $_searchKeyword',
                    style: const TextStyle(
                      color: Colors.teal,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (!_searchMode) ...[
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
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text(
                    '当前为搜索结果，点击右侧返回发现',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _cancelSearch,
                    child: const Text('返回发现'),
                  ),
                ],
              ),
            ),
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
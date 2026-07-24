import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';
import 'package:box/features/api_hub/presentation/api_hub_page.dart';
import 'package:box/features/content/domain/warehouse_models.dart';
import 'package:box/novel/novel_module.dart';
import 'package:box/video_module.dart';

import 'widgets/warehouse_widgets.dart';

class WarehouseTab extends StatefulWidget {
  const WarehouseTab({super.key});

  @override
  State<WarehouseTab> createState() => _WarehouseTabState();
}

class _WarehouseTabState extends State<WarehouseTab>
    with AutomaticKeepAliveClientMixin {
  final WarehouseStore _store = WarehouseStore();

  // 数据状态
  List<WarehouseItem> _bookItems = [];
  List<WarehouseItem> _comicItems = [];
  List<WarehouseItem> _videoItems = [];
  List<WarehouseItem> _musicItems = [];
  bool _booksLoaded = false;
  bool _comicsLoaded = false;
  bool _videosLoaded = false;
  bool _musicLoaded = false;
  bool _loading = true;

  // 错误状态
  bool _booksError = false;
  bool _comicsError = false;
  bool _videosError = false;
  bool _musicError = false;

  // 搜索状态
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showSearch = false;

  // 编辑模式
  bool _editMode = false;
  final Set<String> _selectedKeys = {};

  // 新用户引导
  bool _showOnboarding = true;

  // 懒加载：板块首次可见后标记已加载

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── 数据加载 ──

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    await Future.wait([
      _loadBooks(),
      _loadCategory(WarehouseCategory.comics),
      _loadCategory(WarehouseCategory.videos),
      _loadCategory(WarehouseCategory.music),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    await _loadAllData();
  }

  Future<void> _loadBooks() async {
    try {
      final books = await NovelModule.bookshelf.getBookshelf();
      final now = DateTime.now().millisecondsSinceEpoch;

      final liveItems = books.asMap().entries.map((entry) {
        final index = entry.key;
        final book = entry.value;
        return WarehouseItem(
          id: _readString(book, 'id', fallback: 'book_$index'),
          title: _readString(book, 'title', fallback: '未命名书籍'),
          subtitle: _composeBookSubtitle(book),
          coverUrl: _readString(book, 'coverUrl'),
          detailUrl: _readString(book, 'detailUrl'),
          meta: _readString(book, 'intro'),
          category: WarehouseCategory.books,
          sourceLabel: '书架',
          createdAt: now - index,
          raw: book,
        );
      }).toList();

      final storedItems = await _store.load(WarehouseCategory.books);
      final merged = _mergeItems(liveItems, storedItems);
      if (mounted) {
        setState(() {
          _bookItems = merged;
          _booksLoaded = true;
          _booksError = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _booksLoaded = true; _booksError = true; });
    }
  }

  Future<void> _loadCategory(WarehouseCategory category) async {
    try {
      final items = await _store.load(category);
      if (mounted) {
        setState(() {
          switch (category) {
            case WarehouseCategory.books:
              _bookItems = _mergeItems(_bookItems, items);
              _booksLoaded = true;
              _booksError = false;
            case WarehouseCategory.comics:
              _comicItems = items;
              _comicsLoaded = true;
              _comicsError = false;
            case WarehouseCategory.videos:
              _videoItems = items;
              _videosLoaded = true;
              _videosError = false;
            case WarehouseCategory.music:
              _musicItems = items;
              _musicLoaded = true;
              _musicError = false;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          switch (category) {
            case WarehouseCategory.books:
              _booksLoaded = true;
              _booksError = true;
            case WarehouseCategory.comics:
              _comicsLoaded = true;
              _comicsError = true;
            case WarehouseCategory.videos:
              _videosLoaded = true;
              _videosError = true;
            case WarehouseCategory.music:
              _musicLoaded = true;
              _musicError = true;
          }
        });
      }
    }
  }

  List<WarehouseItem> _mergeItems(
    List<WarehouseItem> liveItems,
    List<WarehouseItem> storedItems,
  ) {
    final map = <String, WarehouseItem>{};
    for (final item in [...liveItems, ...storedItems]) {
      map.putIfAbsent(item.uniqueKey, () => item);
    }
    final list = map.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  String _composeBookSubtitle(dynamic book) {
    final parts = <String>[
      _readString(book, 'author'),
      _readString(book, 'category'),
      _readString(book, 'status'),
    ].where((e) => e.trim().isNotEmpty).toList();
    return parts.join(' · ');
  }

  String _readString(dynamic target, String field, {String fallback = ''}) {
    try {
      final value = (target as dynamic).toJson().cast<String, dynamic>()[field];
      if (value == null) return fallback;
      final text = value.toString().trim();
      return text.isEmpty ? fallback : text;
    } catch (_) {
      try {
        final value = (target as dynamic).toMap().cast<String, dynamic>()[field];
        if (value == null) return fallback;
        final text = value.toString().trim();
        return text.isEmpty ? fallback : text;
      } catch (_) {
        try {
          final value = (target as dynamic).__getattribute__(field);
          if (value == null) return fallback;
          final text = value.toString().trim();
          return text.isEmpty ? fallback : text;
        } catch (_) {
          try {
            final value = (target as dynamic)[field];
            if (value == null) return fallback;
            final text = value.toString().trim();
            return text.isEmpty ? fallback : text;
          } catch (_) {
            return fallback;
          }
        }
      }
    }
  }

  // ── 搜索过滤 ──

  List<WarehouseItem> _filtered(List<WarehouseItem> items) {
    if (_searchQuery.isEmpty) return items;
    final q = _searchQuery.toLowerCase();
    return items.where((item) {
      return item.title.toLowerCase().contains(q) ||
          item.subtitle.toLowerCase().contains(q) ||
          item.meta.toLowerCase().contains(q);
    }).toList();
  }

  int get _totalFiltered =>
      _filtered(_bookItems).length +
      _filtered(_comicItems).length +
      _filtered(_videoItems).length +
      _filtered(_musicItems).length;

  // ── 动态指标 ──

  int get _entryCount => 6;

  int get _sectionCount =>
      (_bookItems.isNotEmpty ? 1 : 0) +
      (_comicItems.isNotEmpty ? 1 : 0) +
      (_videoItems.isNotEmpty ? 1 : 0) +
      (_musicItems.isNotEmpty ? 1 : 0);

  int get _totalItems =>
      _bookItems.length + _comicItems.length +
      _videoItems.length + _musicItems.length;

  String get _syncLabel =>
      _bookItems.where((e) => e.sourceLabel == '书架').isNotEmpty
          ? '已同步'
          : '待同步';

  WarehouseItem? get _recentItem {
    final all = [..._bookItems, ..._comicItems, ..._videoItems, ..._musicItems];
    if (all.isEmpty) return null;
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all.first;
  }

  // ── 编辑模式 ──

  void _enterEditMode() => setState(() {
    _editMode = true;
    _selectedKeys.clear();
  });

  void _exitEditMode() => setState(() {
    _editMode = false;
    _selectedKeys.clear();
  });

  void _toggleSelectItem(String key) {
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
      } else {
        _selectedKeys.add(key);
      }
    });
  }

  Future<void> _batchDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('确认删除'),
        content: Text('将删除 ${_selectedKeys.length} 个收藏项，此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade500),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    for (final key in _selectedKeys) {
      for (final category in WarehouseCategory.values) {
        final items = _itemsForCategory(category);
        final idx = items.indexWhere((e) => e.uniqueKey == key);
        if (idx >= 0) {
          await _store.remove(category, key);
          break;
        }
      }
    }

    _exitEditMode();
    await _refresh();
    if (mounted) _showSnack('已删除 ${_selectedKeys.length} 项');
  }

  List<WarehouseItem> _itemsForCategory(WarehouseCategory category) {
    switch (category) {
      case WarehouseCategory.books: return _bookItems;
      case WarehouseCategory.comics: return _comicItems;
      case WarehouseCategory.videos: return _videoItems;
      case WarehouseCategory.music: return _musicItems;
    }
  }

  // ── 添加对话框 ──

  Future<void> _showAddDialog(WarehouseCategory category) async {
    final titleController = TextEditingController();
    final subtitleController = TextEditingController();
    final coverController = TextEditingController();
    final detailController = TextEditingController();
    final metaController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              CircleAvatar(
                backgroundColor: category.color.withValues(alpha: 0.12),
                child: Icon(category.icon, color: category.color),
              ),
              const SizedBox(width: 10),
              Text('新增${category.hubLabel}'),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.72,
            ),
            child: SizedBox(
              width: double.infinity, // responsive to dialog width
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: titleController,
                        decoration: const InputDecoration(
                            labelText: '名称', hintText: '请输入标题'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? '请输入标题' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: subtitleController,
                        decoration: const InputDecoration(
                            labelText: '副标题',
                            hintText: '作者 / 分类 / 导演 / 艺人'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: coverController,
                        decoration: const InputDecoration(
                            labelText: '封面地址', hintText: 'https://...'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: detailController,
                        decoration: const InputDecoration(
                            labelText: '详情链接', hintText: '可选'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: metaController,
                        decoration: const InputDecoration(
                            labelText: '备注', hintText: '可填写简介、状态等信息'),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.save_rounded),
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final item = WarehouseItem(
                  id: '${category.name}_${DateTime.now().millisecondsSinceEpoch}',
                  title: titleController.text.trim(),
                  subtitle: subtitleController.text.trim(),
                  coverUrl: coverController.text.trim(),
                  detailUrl: detailController.text.trim(),
                  meta: metaController.text.trim(),
                  category: category,
                  sourceLabel: '手动收藏',
                  createdAt: DateTime.now().millisecondsSinceEpoch,
                );
                await _store.add(item);
                if (!mounted || !dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                await _refresh();
                _showSnack('已添加到${category.label}');
              },
              label: const Text('保存收藏'),
            ),
          ],
        );
      },
    );

    titleController.dispose();
    subtitleController.dispose();
    coverController.dispose();
    detailController.dispose();
    metaController.dispose();
  }

  // ── 详情 / 导航 ──

  Future<void> _openItem(WarehouseItem item) async {
    if (item.category == WarehouseCategory.books && item.raw != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => NovelDetailController(entryBook: item.raw),
            child: NovelDetailPage(entryBook: item.raw),
          ),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  CircleAvatar(
                    backgroundColor: item.category.color.withValues(alpha: 0.12),
                    child: Icon(item.category.icon, color: item.category.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(item.title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                ]),
                if (item.subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(item.subtitle,
                      style: TextStyle(color: Colors.grey.shade700)),
                ],
                if (item.meta.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(item.meta,
                      style: TextStyle(
                          color: Colors.grey.shade800, height: 1.45)),
                ],
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  if (item.detailUrl.trim().isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: item.detailUrl));
                        if (!mounted || !sheetContext.mounted) return;
                        Navigator.pop(sheetContext);
                        _showSnack('链接已复制');
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('复制链接'),
                    ),
                  if (item.sourceLabel == '手动收藏')
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _store.remove(item.category, item.uniqueKey);
                        if (!mounted || !sheetContext.mounted) return;
                        Navigator.pop(sheetContext);
                        await _refresh();
                        _showSnack('已移出${item.category.label}');
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('删除'),
                    ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  // ── 入口导航 ──

  void _openVideoCenter() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const VideoListPage()));
  }

  void _openNovelLibrary() {
    Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NovelListPageWithProvider()));
  }

  void _openOpenLibrarySearch() {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => const ApiHubPage(initialTool: 'books')));
  }

  void _openComicsDialog() => _showAddDialog(WarehouseCategory.comics);

  void _openMusicDialog() => _showAddDialog(WarehouseCategory.music);

  void _showQuickImport() => _showCategoryPicker();

  void _dismissOnboarding() => setState(() => _showOnboarding = false);

  Future<void> _showCategoryPicker() async {
    final category = await showModalBottomSheet<WarehouseCategory>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: WarehouseCategory.values.map((category) {
              return ListTile(
                leading: Icon(category.icon, color: category.color),
                title: Text(category.label),
                onTap: () => Navigator.pop(sheetContext, category),
              );
            }).toList(),
          ),
        );
      },
    );
    if (category != null) await _showAddDialog(category);
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Stack(
        children: [
          AppPageScaffold(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                padding: EdgeInsets.fromLTRB(
                  14, 10, 14,
                  _editMode
                      ? AppTokens.pageBottomPadding + 80
                      : AppTokens.pageBottomPadding + 28,
                ),
                children: [
                  ContentHubTopCard(
                    onRefresh: _refresh,
                    entryCount: _entryCount,
                    sectionCount: _sectionCount,
                    totalItems: _totalItems,
                    syncLabel: _syncLabel,
                  ),
                  const SizedBox(height: 10),
                  ContentEntryGrid(
                    onOpenVideoCenter: _openVideoCenter,
                    onOpenNovelLibrary: _openNovelLibrary,
                    onOpenOpenLibrarySearch: _openOpenLibrarySearch,
                    onOpenComics: _openComicsDialog,
                    onOpenMusic: _openMusicDialog,
                    onQuickImport: _showQuickImport,
                  ),
                  const SizedBox(height: 10),
                  ContentOverviewCard(
                    totalItems: _totalItems,
                    recentItem: _recentItem,
                    isLoading: _loading,
                    onOpenItem: _openItem,
                    onQuickImport: _showQuickImport,
                  ),
                  const SizedBox(height: 12),
                  // 新用户引导条
                  if (_showOnboarding && _totalItems == 0 && !_loading) ...[
                    ContentOnboardingBanner(
                      onDismiss: _dismissOnboarding,
                      onQuickImport: _showQuickImport,
                      onSearchBooks: _openOpenLibrarySearch,
                    ),
                    const SizedBox(height: 10),
                  ],
                  // 搜索栏 + 编辑开关
                  Row(
                    children: [
                      Expanded(
                        child: WarehouseSectionHeader(
                          title: '收藏库',
                          subtitle: _showSearch
                              ? '搜索结果：$_totalFiltered 项'
                              : '我的书架 / 影视收藏 / 漫画收藏 / 音乐收藏',
                        ),
                      ),
                      IconButton(
                        tooltip: _showSearch ? '关闭搜索' : '搜索',
                        icon: Icon(
                          _showSearch ? Icons.search_off_rounded : Icons.search_rounded,
                          color: _showSearch ? AppTokens.primaryBlue : Colors.grey.shade600,
                        ),
                        onPressed: () {
                          setState(() {
                            _showSearch = !_showSearch;
                            if (!_showSearch) {
                              _searchController.clear();
                              _searchQuery = '';
                            }
                          });
                        },
                      ),
                      IconButton(
                        tooltip: _editMode ? '完成' : '编辑',
                        icon: Icon(
                          _editMode ? Icons.check_circle_rounded : Icons.edit_outlined,
                          color: _editMode ? AppTokens.emerald : Colors.grey.shade600,
                        ),
                        onPressed: _editMode ? _exitEditMode : _enterEditMode,
                      ),
                    ],
                  ),
                  if (_showSearch) ...[
                    const SizedBox(height: 6),
                    ContentSearchBar(
                      controller: _searchController,
                      onChanged: (q) => setState(() => _searchQuery = q),
                      onClear: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      resultCount: _totalFiltered,
                      isSearching: false,
                    ),
                  ],
                  const SizedBox(height: 10),
                  // 四个收藏分区（搜索模式下只显示有结果的分区）
                  if (_shouldShowSection(WarehouseCategory.books))
                    WarehouseSection(
                      category: WarehouseCategory.books,
                      items: _filtered(_bookItems),
                      isLoading: !_booksLoaded,
                      hasError: _booksError,
                      emptyText: '从小说书架同步最近阅读，也可以手动收藏书籍链接',
                      onAdd: _showAddDialog,
                      onOpenItem: _openItem,
                      onOpenVideoCenter: _openVideoCenter,
                      onOpenNovelLibrary: _openNovelLibrary,
                      editMode: _editMode,
                      selectedKeys: _selectedKeys,
                      onToggleSelect: _toggleSelectItem,
                    ),
                  if (_shouldShowSection(WarehouseCategory.comics)) ...[
                    const SizedBox(height: 12),
                    WarehouseSection(
                      category: WarehouseCategory.comics,
                      items: _filtered(_comicItems),
                      isLoading: !_comicsLoaded,
                      hasError: _comicsError,
                      emptyText: '漫画资源会集中放在这里，方便后续扩展漫画入口',
                      onAdd: _showAddDialog,
                      onOpenItem: _openItem,
                      onOpenVideoCenter: _openVideoCenter,
                      onOpenNovelLibrary: _openNovelLibrary,
                      editMode: _editMode,
                      selectedKeys: _selectedKeys,
                      onToggleSelect: _toggleSelectItem,
                    ),
                  ],
                  if (_shouldShowSection(WarehouseCategory.videos)) ...[
                    const SizedBox(height: 12),
                    WarehouseSection(
                      category: WarehouseCategory.videos,
                      items: _filtered(_videoItems),
                      isLoading: !_videosLoaded,
                      hasError: _videosError,
                      emptyText: '先去影视搜索发现内容，后续播放历史和收藏会聚合到这里',
                      onAdd: _showAddDialog,
                      onOpenItem: _openItem,
                      onOpenVideoCenter: _openVideoCenter,
                      onOpenNovelLibrary: _openNovelLibrary,
                      editMode: _editMode,
                      selectedKeys: _selectedKeys,
                      onToggleSelect: _toggleSelectItem,
                    ),
                  ],
                  if (_shouldShowSection(WarehouseCategory.music)) ...[
                    const SizedBox(height: 12),
                    WarehouseSection(
                      category: WarehouseCategory.music,
                      items: _filtered(_musicItems),
                      isLoading: !_musicLoaded,
                      hasError: _musicError,
                      emptyText: '音乐链接、歌单和历史记录会集中收纳到这里',
                      onAdd: _showAddDialog,
                      onOpenItem: _openItem,
                      onOpenVideoCenter: _openVideoCenter,
                      onOpenNovelLibrary: _openNovelLibrary,
                      editMode: _editMode,
                      selectedKeys: _selectedKeys,
                      onToggleSelect: _toggleSelectItem,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // 批量操作栏
          if (_editMode)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: BatchActionBar(
                selectedCount: _selectedKeys.length,
                onDelete: _batchDelete,
                onCancel: _exitEditMode,
              ),
            ),
        ],
      ),
    );
  }

  /// 判断分区是否应该显示：搜索时只显示有结果的分区
  bool _shouldShowSection(WarehouseCategory category) {
    if (_searchQuery.isNotEmpty) {
      switch (category) {
        case WarehouseCategory.books:
          return _filtered(_bookItems).isNotEmpty;
        case WarehouseCategory.comics:
          return _filtered(_comicItems).isNotEmpty;
        case WarehouseCategory.videos:
          return _filtered(_videoItems).isNotEmpty;
        case WarehouseCategory.music:
          return _filtered(_musicItems).isNotEmpty;
      }
    }
    return true;
  }
}

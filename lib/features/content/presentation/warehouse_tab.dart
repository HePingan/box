import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart';
import 'package:box/design_system/widgets/app_page_scaffold.dart';
import 'package:box/features/comic/presentation/comic_library_page.dart';
import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/presentation/comic_reader_page.dart';
import 'package:box/novel/core/models.dart';
import 'package:box/novel/pages/reader_page.dart';
import 'package:box/features/content/domain/warehouse_adapters.dart';
import 'package:box/features/content/domain/warehouse_cleanup.dart';
import 'package:box/features/content/domain/warehouse_models.dart';
import 'package:box/features/content/presentation/warehouse_search.dart';
import 'package:box/features/music/presentation/music_placeholder_page.dart';
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
  //
  // 三条**实时**数据通道，各自独立存储：
  //  * books  —— NovelModule.bookshelf（小说书架）
  //  * videos —— FavoritesRepository（Hive video_favorites_box，追剧收藏）
  //  * comics —— ComicLibraryStore（CacheStore comic_library，本地漫画）
  //
  // 影视/漫画此前没接进来（`_itemsForCategory` 对非 books 恒返回 const []），
  // 于是 Hive 里明明有收藏，页面却永远空白 —— 这就是用户报的
  // 「内容页收藏库影视收藏没显示出来」。
  //
  // music 仍无数据通道（播放器未开发，入口进占位页），所以不建状态字段。
  List<WarehouseItem> _bookItems = [];
  List<WarehouseItem> _videoItems = [];
  List<WarehouseItem> _comicItems = [];
  bool _booksLoaded = false;
  bool _videosLoaded = false;
  bool _comicsLoaded = false;
  bool _loading = true;
  bool _booksError = false;
  bool _videosError = false;
  bool _comicsError = false;

  /// 正在取详情准备进阅读器的书 id（null = 没有）。
  /// 详情缓存未命中要走网络，没有这个遮罩用户会以为点了没反应而反复点。
  String? _openingBookKey;

  final ComicLibraryStore _comicStore = ComicLibraryStore();
  final FavoritesRepository _favoritesRepo = FavoritesRepository();

  // 搜索状态
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  bool _showSearch = false;

  // 编辑模式
  bool _editMode = false;
  final Set<String> _selectedKeys = {};

  // 懒加载：板块首次可见后标记已加载

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    // 这里原本挂了个 800ms 延迟的「自动同步」：本地没数据时调 _syncFromCloud()。
    // 而 _syncFromCloud 现在就是重读本地三条通道，_loadAllData() 刚做完同一件事，
    // 留着只是让空库用户白等 800ms 再读一遍 IO，所以撤掉。
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── 数据加载 ──

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    // 手填条目已随入口下线，先做一次性清理再读书架。
    // 清理只删 sourceLabel == 手动收藏 的条目，书架数据是另一条通道，不受影响。
    await _purgeLegacyManualEntries();
    // 三条通道互不依赖，并行加载：串行会让首屏等三次 IO。
    // 单条失败只影响自己的分区（各自有 error 标记），不拖垮整页。
    await Future.wait([_loadBooks(), _loadVideoFavorites(), _loadComics()]);
    if (mounted) setState(() => _loading = false);
  }

  /// 影视收藏（Hive `video_favorites_box`）。
  ///
  /// 直接走 [FavoritesRepository] 而不是 context 里的 FavoritesController：
  /// 收藏库要在页面 initState 阶段就拿到数据，而 controller 的 load() 由
  /// app_shell 在别处触发，时机不保证；repository 自带 init() 幂等打开 box。
  Future<void> _loadVideoFavorites() async {
    try {
      await _favoritesRepo.init();
      final items = warehouseItemsFromFavorites(_favoritesRepo.getAll());
      if (mounted) {
        setState(() {
          _videoItems = items;
          _videosLoaded = true;
          _videosError = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _videosLoaded = true;
          _videosError = true;
        });
      }
    }
  }

  /// 漫画收藏（CacheStore `comic_library`，本地导入的 CBZ/ZIP/文件夹）。
  Future<void> _loadComics() async {
    try {
      final books = await _comicStore.fetch();
      final items = warehouseItemsFromComicBooks(books);
      if (mounted) {
        setState(() {
          _comicItems = items;
          _comicsLoaded = true;
          _comicsError = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _comicsLoaded = true;
          _comicsError = true;
        });
      }
    }
  }

  /// 一次性清掉手填收藏残留。失败不阻塞页面加载。
  Future<void> _purgeLegacyManualEntries() async {
    try {
      await WarehouseCleanup(store: _store).run();
    } catch (_) {
      // 清理失败不影响正常浏览：手填条目已无入口，下次进页面会再试。
    }
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
      if (mounted) {
        setState(() {
          _booksLoaded = true;
          _booksError = true;
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
        final value = (target as dynamic)
            .toMap()
            .cast<String, dynamic>()[field];
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

  List<WarehouseItem> _filtered(List<WarehouseItem> items) =>
      warehouseFilter(items, _searchQuery);

  /// 搜到没有 != 一本都没有。前者要提示换词，后者走分区自己的空态引导。
  bool get _isNoSearchResult => isWarehouseNoSearchResult(
    query: _searchQuery,
    totalItemsInLibrary: _totalItems,
    totalMatched: _totalFiltered,
  );

  /// 搜索词变化时把选中集收敛到仍可见的项，避免删掉屏幕上看不见的收藏。
  void _applySearchQuery(String query) {
    setState(() {
      _searchQuery = query;
      if (_editMode && _selectedKeys.isNotEmpty) {
        // 收敛范围必须覆盖全部分区，只看 books 会让搜索时残留的
        // 影视/漫画选中项躲过收敛，被批量删除悄悄带走。
        final visible = _allSections.expand(_filtered).toList();
        final kept = retainVisibleSelection(
          selected: _selectedKeys,
          visibleItems: visible,
        );
        _selectedKeys
          ..clear()
          ..addAll(kept);
      }
    });
  }

  /// 全部分区，顺序即页面渲染顺序。
  ///
  /// 单一事实源：统计、搜索收敛、最近收藏、批量删除全部从这里取，
  /// 避免再出现「接了新分区但某个统计忘了改」的漂移。
  List<List<WarehouseItem>> get _allSections => [
    _bookItems,
    _videoItems,
    _comicItems,
  ];

  int get _totalFiltered =>
      _allSections.fold(0, (sum, s) => sum + _filtered(s).length);

  // ── 动态指标 ──

  /// 内容入口数：影视 / 小说 / 漫画 / 音乐。
  /// 这里以前硬编码 6，改成四宫格后不改会让顶部统计撒谎。
  int get _entryCount => 4;

  int get _sectionCount => warehouseNonEmptySectionCount(_allSections);

  int get _totalItems => warehouseTotalItems(_allSections);

  /// 同步状态标签。
  ///
  /// 判定改为「三条实时通道是否都已读完」，而不是原来的
  /// 「books 里有没有 sourceLabel == 书架 的条目」—— 后者在书架为空时
  /// 恒显示「待同步」，而其实已经同步完了，只是没有书。
  String get _syncLabel {
    if (!_booksLoaded || !_videosLoaded || !_comicsLoaded) return '读取中';
    if (_booksError || _videosError || _comicsError) return '部分失败';
    return '本地已就绪';
  }

  WarehouseItem? get _recentItem {
    final all = _allSections.expand((e) => e).toList();
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade500),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 删除必须打到条目真正所在的那个存储。
    //
    // 原实现一律调 `_store.remove(...)`（warehouse_center namespace），
    // 而三个分区的数据其实都不在那里：书架在 BookshelfManager、影视在 Hive
    // video_favorites_box、漫画在 comic_library。结果是弹「已删除 N 项」，
    // 刷新后条目原封不动 —— 静默失效。
    var deletedCount = 0;
    var failedCount = 0;
    for (final key in _selectedKeys) {
      final item = _findItemByKey(key);
      if (item == null) continue;
      try {
        await _deleteItem(item);
        deletedCount++;
      } catch (_) {
        failedCount++;
      }
    }

    _exitEditMode();
    await _refresh();
    if (mounted) {
      _showSnack(
        failedCount == 0 ? '已删除 $deletedCount 项' : '已删除 $deletedCount 项，$failedCount 项失败',
      );
    }
  }

  WarehouseItem? _findItemByKey(String key) {
    for (final section in _allSections) {
      for (final item in section) {
        if (item.uniqueKey == key) return item;
      }
    }
    return null;
  }

  /// 把删除请求路由到条目真正所在的存储。
  Future<void> _deleteItem(WarehouseItem item) async {
    switch (item.category) {
      case WarehouseCategory.books:
        // 书架条目的 id 就是 NovelBook.id（见 _loadBooks）。
        await NovelModule.bookshelf.removeFromBookshelf(item.id);
      case WarehouseCategory.videos:
        // item.id 就是 Hive 存储键 `sourceId::vodId`（见 warehouse_adapters），
        // 走 removeByKey 就不必反查 VideoSource 实例。
        await _favoritesRepo.removeByKey(item.id);
      case WarehouseCategory.comics:
        await _comicStore.remove(item.id);
      case WarehouseCategory.music:
        // 无数据通道，理论上不会有条目落到这里。
        break;
    }
  }

  // ── 云端同步 ──

  bool _syncing = false;
  String? _syncStatus;

  Future<void> _syncFromCloud() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncStatus = '同步中…';
    });

    // 这里原本是 `await Future.delayed(1s)` 然后无条件写「已同步（本地优先）」
    // —— 什么都没同步，纯粹在骗用户。云端收藏同步服务端还没有，
    // 所以这个按钮现在只做它真能做到的事：重新读三条本地通道。
    // 文案也如实说明是本地刷新，不再暗示有云端。
    try {
      await _refresh();
      if (!mounted) return;
      final failed = _booksError || _videosError || _comicsError;
      setState(() {
        _syncing = false;
        _syncStatus = failed ? '部分读取失败' : '已刷新 $_totalItems 项';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _syncStatus = '刷新失败';
      });
      debugPrint('[warehouse] 本地收藏刷新失败: $e');
    }
  }

  // ── 详情 / 导航 ──

  /// 收藏库点书 → 直接进阅读器续读。
  ///
  /// 用户原来的路径是：点书 → 详情页 → 再点「继续阅读」，两步才开始读。
  /// 这里合成一步。
  ///
  /// 障碍：书架存的 [NovelBook] 不含章节列表（`getBookshelfBooks()` 返回
  /// `chapters: const []`），而 [ReaderPage] 必须要有 `detail.chapters`。
  /// 所以必须先 `fetchDetail` —— 有 8h 缓存，命中时几乎瞬时；未命中就要走网络，
  /// 因此加载期间显示遮罩，失败退回详情页而不是把用户卡在原地。
  Future<void> _openBookForReading(NovelBook book) async {
    setState(() => _openingBookKey = book.id);
    NovelDetail? detail;
    try {
      detail = await NovelModule.repository.fetchDetail(
        bookId: book.id,
        detailUrl: book.detailUrl,
      );
    } catch (e) {
      debugPrint('[warehouse] 取书籍详情失败，退回详情页: $e');
    }
    if (!mounted) return;
    setState(() => _openingBookKey = null);

    // 章节拿不到就无法进阅读器，退回详情页让用户自己重试/换源。
    if (detail == null || detail.chapters.isEmpty) {
      await _pushNovelDetail(book);
      return;
    }

    // 续读定位：有进度就回到那一章，没有就从第一章开始。
    int chapterIndex = 0;
    try {
      final progress = await NovelModule.repository.getProgress(book.id);
      if (progress != null) {
        chapterIndex = progress.chapterIndex.clamp(0, detail.chapters.length - 1);
      }
    } catch (e) {
      debugPrint('[warehouse] 读取阅读进度失败，从头开始: $e');
    }
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReaderPage(detail: detail!, initialChapterIndex: chapterIndex),
      ),
    );
    // 回来刷新书架，让「读到第几章」的副标题跟上。
    if (mounted) await _loadBooks();
  }

  Future<void> _pushNovelDetail(NovelBook book) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => NovelDetailController(entryBook: book),
          child: NovelDetailPage(entryBook: book),
        ),
      ),
    );
    if (mounted) await _loadBooks();
  }

  /// 影视收藏 → 视频详情页。返回 false 表示没跳成功（调用方退回详情浮层）。
  Future<bool> _openVideoFavorite(WarehouseItem item) async {
    final fav = item.raw;
    if (fav is! FavoriteItem) return false;
    if (!mounted) return true;

    // 片源列表由 VideoController 持有；收藏只存了 sourceId/sourceUrl 字符串。
    final videoController = context.read<VideoController>();
    final source = findVideoSourceForFavorite(videoController.sources, fav);
    if (source == null) {
      _showSnack('该视频的片源已失效或被移除');
      return true;
    }
    if (fav.vodId <= 0) {
      _showSnack('收藏记录中的视频ID无效');
      return true;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoDetailPage(source: source, vodId: fav.vodId),
      ),
    );
    if (mounted) await _loadVideoFavorites();
    return true;
  }

  Future<void> _openItem(WarehouseItem item) async {
    // 每个分区都跳到「用户点这个卡片时真正想去的地方」，
    // 而不是统一弹一个只能看不能用的详情浮层。
    switch (item.category) {
      case WarehouseCategory.books:
        if (item.raw is NovelBook) {
          await _openBookForReading(item.raw as NovelBook);
          return;
        }
      case WarehouseCategory.videos:
        if (await _openVideoFavorite(item)) return;
      case WarehouseCategory.comics:
        if (item.raw is ComicBook) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ComicReaderPage(comicBook: item.raw as ComicBook),
            ),
          );
          if (mounted) await _loadComics();
          return;
        }
      case WarehouseCategory.music:
        break;
    }

    // 兜底：拿不到跳转所需的原始对象时才退回详情浮层。
    // 上面各分支可能 await 过（_openVideoFavorite），这里必须重新确认还挂着。
    if (!mounted) return;
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
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: item.category.color.withValues(
                        alpha: 0.12,
                      ),
                      child: Icon(
                        item.category.icon,
                        color: item.category.color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    item.subtitle,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
                if (item.meta.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    item.meta,
                    style: TextStyle(color: Colors.grey.shade800, height: 1.45),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (item.detailUrl.trim().isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: item.detailUrl),
                          );
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
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ── 入口导航 ──

  void _openVideoCenter() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VideoListPage()),
    );
  }

  void _openNovelLibrary() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NovelListPageWithProvider()),
    );
  }

  void _openComics() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ComicLibraryPage()),
    );
  }

  /// 音乐入口：播放器尚未开发。
  ///
  /// 以前这里是「滚动定位到同页音乐收藏区块」，那是手填收藏时代的兜底：
  /// 音乐当时只是仓库的一个收藏分类。手填入口整体撤掉后该区块不再有数据，
  /// 滚过去只会看到空白，比明说「开发中」更像功能坏了。
  /// 现在进占位页，页面里写清规划（本地播放 + 在线源爬取下载）。
  void _openMusic() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MusicPlaceholderPage()),
    );
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
            maxContentWidth: AppTokens.shellMaxContentWidth,
            shellInset: true,
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  AppTokens.shellPageGutter,
                  10,
                  AppTokens.shellPageGutter,
                  // 基础避让由 AppPageScaffold(shellInset: true) 下发；
                  // 编辑态底部另有批量操作条，再加高 68。
                  AppPageScaffold.bottomInsetOf(
                    context,
                    extra: _editMode ? 68 : 0,
                  ),
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
                    onOpenComics: _openComics,
                    onOpenMusic: _openMusic,
                  ),
                  const SizedBox(height: 10),
                  // 最近收藏：仅在非空或加载中时显示
                  if (_totalItems > 0 || _loading) ...[
                    ContentOverviewCard(
                      totalItems: _totalItems,
                      recentItem: _recentItem,
                      isLoading: _loading,
                      onOpenItem: _openItem,
                    ),
                    const SizedBox(height: 12),
                  ],
                  // 搜索栏 + 编辑开关
                  Row(
                    children: [
                      Expanded(
                        child: WarehouseSectionHeader(
                          title: '收藏库',
                          subtitle: _showSearch
                              ? '搜索结果：$_totalFiltered 项'
                              // 只列真的有数据通道的三个分区。
                              // 音乐播放器未开发，写进来就是承诺一个不存在的功能。
                              : '我的书架 / 影视收藏 / 漫画收藏',
                        ),
                      ),
                      IconButton(
                        tooltip: _showSearch ? '关闭搜索' : '搜索',
                        icon: Icon(
                          _showSearch
                              ? Icons.search_off_rounded
                              : Icons.search_rounded,
                          color: _showSearch
                              ? AppTokens.primaryBlue
                              : Colors.grey.shade600,
                        ),
                        onPressed: () {
                          setState(() {
                            _showSearch = !_showSearch;
                            if (!_showSearch) {
                              // 关闭搜索时同样要收敛选中集，否则残留的
                              // 不可见选中项会被批量删除带走。
                              _searchDebounce?.cancel();
                              _searchController.clear();
                              _searchQuery = '';
                            }
                          });
                        },
                      ),
                      IconButton(
                        tooltip: _editMode ? '完成' : '编辑',
                        icon: Icon(
                          _editMode
                              ? Icons.check_circle_rounded
                              : Icons.edit_outlined,
                          color: _editMode
                              ? AppTokens.emerald
                              : Colors.grey.shade600,
                        ),
                        onPressed: _editMode ? _exitEditMode : _enterEditMode,
                      ),
                    ],
                  ),
                  // 同步按钮独占一行右对齐。
                  // 这里原本还有一个常显的 ContentSearchBar，与下方受
                  // _showSearch 控制的那个共用同一个 _searchController：
                  // 两个搜索框同时挂同一 controller，放大镜按钮形同虚设，
                  // 且层级上一个裸在卡片外、一个在卡片内，视觉不齐。
                  // 现只保留 _showSearch 控制的那一个。
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      InkWell(
                        onTap: _syncing ? null : () => _syncFromCloud(),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _syncing
                                ? Colors.grey.shade100
                                : AppTokens.emerald.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_syncing)
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                  ),
                                )
                              else
                                const Icon(
                                  Icons.sync_rounded,
                                  size: 14,
                                  color: AppTokens.emerald,
                                ),
                              const SizedBox(width: 4),
                              Text(
                                // 「同步」会被理解成云端同步，实际只是重读本地。
                                _syncStatus ?? '刷新',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _syncing
                                      ? Colors.grey.shade600
                                      : AppTokens.emerald,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_showSearch) ...[
                    const SizedBox(height: 6),
                    // 收进与「内容入口」「收藏分区」同规格的卡片容器
                    // （白 0.94 / radiusMd / AppTokens.cardBorder），
                    // 原来搜索框自带一层边框却裸在卡片流之外，层级不齐。
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(
                          AppTokens.radiusMd,
                        ),
                        border: Border.all(color: AppTokens.cardBorder),
                      ),
                      child: ContentSearchBar(
                        controller: _searchController,
                        framed: false,
                        onChanged: (q) {
                          _searchDebounce?.cancel();
                          _searchDebounce = Timer(
                            const Duration(milliseconds: 300),
                            () {
                              if (!mounted) return;
                              _applySearchQuery(q);
                            },
                          );
                        },
                        onClear: () {
                          _searchDebounce?.cancel();
                          _searchController.clear();
                          _applySearchQuery('');
                        },
                        resultCount: _totalFiltered,
                        isSearching: false,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // 搜索零命中：四个分区会全部隐藏，这里必须给出明确反馈，
                  // 否则页面上只剩顶部卡片和搜索框，像是收藏被清空了。
                  if (_isNoSearchResult)
                    AppEmptyState(
                      icon: Icons.search_off_rounded,
                      title: '没有匹配「$_searchQuery」的收藏',
                      message: '换个关键词试试，或清除搜索查看全部 $_totalItems 项收藏。',
                      actionLabel: '清除搜索',
                      onAction: () {
                        _searchDebounce?.cancel();
                        _searchController.clear();
                        _applySearchQuery('');
                      },
                    ),
                  // 三个实时分区：书架 / 影视收藏 / 漫画收藏。
                  //
                  // music 不建分区：播放器还没做，入口进占位页，
                  // 建一个永远空白的分区比不建更像功能坏了。
                  if (_shouldShowSection(WarehouseCategory.books))
                    WarehouseSection(
                      category: WarehouseCategory.books,
                      items: _filtered(_bookItems),
                      isLoading: !_booksLoaded,
                      hasError: _booksError,
                      emptyText: '从小说书架同步最近阅读的书籍',
                      onOpenItem: _openItem,
                      onOpenVideoCenter: _openVideoCenter,
                      onOpenNovelLibrary: _openNovelLibrary,
                      editMode: _editMode,
                      selectedKeys: _selectedKeys,
                      onToggleSelect: _toggleSelectItem,
                      searchQuery: _searchQuery,
                    ),
                  if (_shouldShowSection(WarehouseCategory.videos)) ...[
                    const SizedBox(height: 10),
                    WarehouseSection(
                      category: WarehouseCategory.videos,
                      items: _filtered(_videoItems),
                      isLoading: !_videosLoaded,
                      hasError: _videosError,
                      emptyText: '在影视详情页点收藏，这里就会出现',
                      onOpenItem: _openItem,
                      onOpenVideoCenter: _openVideoCenter,
                      onOpenNovelLibrary: _openNovelLibrary,
                      editMode: _editMode,
                      selectedKeys: _selectedKeys,
                      onToggleSelect: _toggleSelectItem,
                      searchQuery: _searchQuery,
                    ),
                  ],
                  if (_shouldShowSection(WarehouseCategory.comics)) ...[
                    const SizedBox(height: 10),
                    WarehouseSection(
                      category: WarehouseCategory.comics,
                      items: _filtered(_comicItems),
                      isLoading: !_comicsLoaded,
                      hasError: _comicsError,
                      emptyText: '在漫画库导入 CBZ/ZIP 或文件夹',
                      onOpenItem: _openItem,
                      onOpenVideoCenter: _openVideoCenter,
                      onOpenNovelLibrary: _openNovelLibrary,
                      editMode: _editMode,
                      selectedKeys: _selectedKeys,
                      onToggleSelect: _toggleSelectItem,
                      searchQuery: _searchQuery,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // 批量操作栏
          if (_editMode)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BatchActionBar(
                selectedCount: _selectedKeys.length,
                onDelete: _batchDelete,
                onCancel: _exitEditMode,
              ),
            ),
          // 点书直接进阅读器时，取详情可能要走网络（缓存未命中）。
          // 没有这层遮罩用户会以为点了没反应而反复点，重复触发跳转。
          if (_openingBookKey != null)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('正在打开…'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 判断分区是否应该显示：搜索时只显示有结果的分区。
  ///
  /// 判定逻辑收敛到 [shouldShowWarehouseSection]，不再按分类硬编码 false
  /// —— 原实现对 videos/comics/music 一律 return false，是「影视收藏
  /// 搜不出来」的直接原因。
  bool _shouldShowSection(WarehouseCategory category) {
    return shouldShowWarehouseSection(
      searchQuery: _searchQuery,
      matchedInSection: _filtered(_itemsForCategory(category)),
    );
  }

  List<WarehouseItem> _itemsForCategory(WarehouseCategory category) {
    switch (category) {
      case WarehouseCategory.books:
        return _bookItems;
      case WarehouseCategory.videos:
        return _videoItems;
      case WarehouseCategory.comics:
        return _comicItems;
      case WarehouseCategory.music:
        return const [];
    }
  }
}

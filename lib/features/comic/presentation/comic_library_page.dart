import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/comic/domain/comic_fetcher.dart';
import 'package:box/features/comic/domain/comic_image_cache.dart';
import 'package:box/features/comic/domain/comic_offline_store.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/domain/comic_online_progress.dart';
import 'package:box/features/comic/domain/comic_update_watch.dart';
import 'package:box/features/comic/data/comic_sync_ops.dart';
import 'package:box/features/comic/presentation/comic_online_page.dart';
import 'package:box/features/comic/domain/comic_reader_state.dart';
import 'package:box/features/comic/infrastructure/comic_importer_widget.dart';
import 'package:box/features/comic/presentation/comic_reader_page.dart';
import 'package:box/features/comic/presentation/comic_source_check_page.dart';
import 'package:box/features/comic/presentation/comic_cover_image.dart';

/// 书架一行的展示数据：漫画本体 + 它的真实阅读进度（没读过就是 null）。
class _ShelfEntry {
  const _ShelfEntry({
    required this.book,
    this.progress,
    this.onlineProgress,
    this.newChapters = 0,
  });

  final ComicBook book;

  /// 追更查到的新话数（在线书才有；本地漫画恒为 0）。
  final int newChapters;

  final ComicReaderState? progress;

  /// 在线书的阅读进度（读到哪一话）；本地书为 null。
  final ComicOnlineProgress? onlineProgress;

  /// 在线书的进度文案（有进度才给；没有就说"还没看过"，不编造）。
  String? get onlineLabel {
    final p = onlineProgress;
    if (p == null) return null;
    final t = p.chapterTitle.trim();
    return t.isEmpty ? '读到第 ${p.index + 1} 张' : '读到 $t';
  }

  /// 读到的百分比；无进度或总页数未知时返回 null，绝不凭空造 0%。
  int? get percent {
    final state = progress;
    if (state == null) return null;
    final total = state.totalPages > 0 ? state.totalPages : book.pages.length;
    if (total <= 0) return null;
    final value = ((state.currentPageIndex + 1) / total * 100).round();
    return value.clamp(1, 100);
  }
}

/// 漫画库页面（本地收藏书架）。
///
/// 本页只管本地导入的漫画（CBZ/ZIP/文件夹）。在线漫画源不内置在 App 里，
/// 由用户通过插件市场自行安装。
class ComicLibraryPage extends StatefulWidget {
  const ComicLibraryPage({
    super.key,
    this.libraryStore,
    this.onlineProgressStore,
    this.coverCache,
    this.offlineStore,
  });

  /// 可注入存储（测试用）；生产省略即走默认实例。
  final ComicLibraryStore? libraryStore;

  /// 可注入的封面缓存（测试用）；生产省略即走"带手机 UA"的默认缓存。
  final ComicImageCache? coverCache;

  /// 离线库（测试注入用）。
  final ComicOfflineStore? offlineStore;

  /// 在线阅读进度的存储（测试用内存版）；生产省略即走默认实例。
  final ComicOnlineProgressStore? onlineProgressStore;

  @override
  State<ComicLibraryPage> createState() => _ComicLibraryPageState();
}

class _ComicLibraryPageState extends State<ComicLibraryPage> {
  late final ComicLibraryStore _store;
  late Future<List<_ShelfEntry>> _future;

  /// 中转要用的设备令牌（在线页读中转时带上）。null = 还没读到，让在线页自己去读。
  /// **可选**：没配就是直连站点（手机能到），不是错误。
  String? _relayToken;

  /// 封面缓存（带请求头 + 落本地）。
  ///
  /// 封面地址都在直连图床上，跟章节图一样**要带手机 UA** 才下得来；以前这里用
  /// Flutter 自带的 `Image.network`（一份头都不带），图床把请求丢掉，界面上只剩一个
  /// 破图标 —— 用户只能说"封面加载不出来"，我这边也无从判断（2026-09-29）。
  /// 这里**不带设备令牌**：令牌只发给自己的中转，发给第三方图床就是泄露。
  late final ComicImageCache _coverCache =
      widget.coverCache ??
      ComicImageCache(headerFor: (url) => comicDirectHeaders());

  /// 离线库：封面先问本机（下载过的书断网也看得见封面）。
  late final ComicOfflineStore _offline =
      widget.offlineStore ?? ComicOfflineStore();

  /// 追更记录本（与内容页是**同一份记录**：两处看到的是同一个"有没有新话"）。
  ComicUpdateWatch? _updates;
  bool _updatesReady = false;

  @override
  void initState() {
    super.initState();
    _store = widget.libraryStore ?? ComicLibraryStore();
    // 预热离线库：下载过的书断网时封面/阅读都能直接读本机那份。
    unawaited(_offline.warmUp());
    _future = _load();
    unawaited(() async {
      await _ensureUpdates();
      await _checkComicUpdates();
    }());
    // 令牌读一次就够（用户改了设置再进本页也会重新读）。读不出来保持 null：
    // 在线页会自己去读，读不到就直连站点（不是错误）。
    loadComicRelayToken().then((t) {
      if (mounted && t.isNotEmpty) setState(() => _relayToken = t);
    });
  }

  Future<void> _ensureUpdates() async {
    if (_updatesReady) return;
    _updatesReady = true;
    final source = ComicUpdateWatch.defaultComicSource();
    if (source == null) return;
    var token = '';
    try {
      token = await loadComicRelayToken();
    } catch (_) {
      token = '';
    }
    _updates = ComicUpdateWatch(
      source: source,
      fetcher: comicUpdateFetcher(source, token),
    );
  }

  Future<void> _checkComicUpdates({bool force = false}) async {
    final watch = _updates;
    if (watch == null) return;
    final urls = <String>[
      for (final e in await _store.fetch())
        if (e.isOnline) e.onlineUrl!,
    ];
    if (urls.isEmpty) return;
    final got = await watch.checkDue(urls, force: force);
    if (!mounted || !got.values.any((r) => r.hasNew)) return;
    setState(() => _future = _load()); // 有动静才重画
  }

  Future<List<_ShelfEntry>> _load() async {
    final books = await _store.fetch();
    await _ensureUpdates();
    final entries = <_ShelfEntry>[];
    final onlineStore = widget.onlineProgressStore ?? ComicOnlineProgressStore();
    for (final book in books) {
      final isOnline = book.isOnline;
      entries.add(
        _ShelfEntry(
          book: book,
          progress: isOnline ? null : await _store.loadProgress(book.id),
          onlineProgress:
              isOnline ? await onlineStore.load(book.onlineUrl!) : null,
          newChapters: isOnline ? await _newChaptersOf(book.onlineUrl!) : 0,
        ),
      );
    }
    return entries;
  }

  /// 这本书查到的新话数（没查过/没有就是 0）。
  Future<int> _newChaptersOf(String bookUrl) async {
    final watch = _updates;
    if (watch == null) return 0;
    try {
      final rec = await watch.read(bookUrl);
      return rec?.newCount ?? 0;
    } catch (_) {
      return 0; // 读不出来就是"没有新话"：角标不值得让整页出错
    }
  }

  void _reload() {
    // 注意：闭包必须是 void，不能写 `() => _future = _load()`——那会把 Future
    // 作为闭包返回值交给 setState，Flutter 会直接断言失败。
    setState(() {
      _future = _load();
    });
  }

  Future<void> _importFlow() async {
    final book = await showDialog<ComicBook>(
      context: context,
      builder: (_) => _ImportDialog(store: _store),
    );
    if (book != null && mounted) _reload();
  }

  Future<void> _openReader(ComicBook book) async {
    final url = book.onlineUrl ?? '';
    if (book.isOnline) {
      // 在线书：进在线页并直接打开这本书（进度在那边按书链记，回来刷新角标）
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ComicOnlinePage(
            initialBookUrl: url,
            relayToken: _relayToken,
          ),
        ),
      );
      if (mounted) _reload();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComicReaderPage(comicBook: book, libraryStore: _store),
      ),
    );
    // 从阅读器回来，进度角标要跟着更新。
    if (mounted) _reload();
  }

  Future<void> _confirmDelete(ComicBook book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除漫画'),
        content: Text('确定从收藏里移除《${book.title}》吗？原始文件不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _store.remove(book.id);
    // 把"删了这本书"记成墓碑再同步：不然别的设备上它还留着，下次同步又把它推回来
    // （删除必须传得出去，这是跨设备同步最容易漏的一环）。
    if (book.sourceType == ComicSourceType.online) {
      unawaited(_syncRemoved(book.onlineUrl ?? book.id));
    }
    if (mounted) _reload();
  }

  /// 记墓碑 + 顺带同步一次；失败不弹错（删除已经落本地了，同步下次还会再试）。
  Future<void> _syncRemoved(String bookUrl) async {
    try {
      final sync = await createComicSyncService();
      if (sync == null) return;
      await sync.recordRemoved(bookUrl);
      await sync.syncNow();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('漫画收藏'),
        actions: [
          IconButton(
            tooltip: '在线漫画（搜索/阅读）',
            icon: const Icon(Icons.travel_explore_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ComicOnlinePage(relayToken: _relayToken),
              ),
            ),
          ),
          IconButton(
            tooltip: '漫画源自检',
            icon: const Icon(Icons.health_and_safety_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ComicSourceCheckPage()),
            ),
          ),
          IconButton(
            tooltip: '导入漫画',
            icon: const Icon(Icons.add),
            onPressed: _importFlow,
          ),
        ],
      ),
      body: FutureBuilder<List<_ShelfEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败: ${snapshot.error}'));
          }

          final entries = snapshot.data ?? const <_ShelfEntry>[];
          if (entries.isEmpty) return _buildEmpty();

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.7,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _ComicBookCard(
                entry: entry,
                cache: _coverCache,
                offline: _offline,
                onTap: () => _openReader(entry.book),
                onDelete: () => _confirmDelete(entry.book),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.collections_bookmark_outlined, size: 64),
          const SizedBox(height: 16),
          const Text('还没有漫画'),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '本地：导入 CBZ / ZIP 或图片文件夹。\n'
              '在线：点右上角「地球」搜索阅读，在书的详情里点「加入书架」就会出现在这里；\n'
              '「盾牌」图标是源的自检。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _importFlow,
            child: const Text('导入漫画'),
          ),
        ],
      ),
    );
  }
}

class _ComicBookCard extends StatelessWidget {
  const _ComicBookCard({
    required this.entry,
    required this.cache,
    required this.offline,
    required this.onTap,
    required this.onDelete,
  });

  final _ShelfEntry entry;

  /// 封面走的缓存（带请求头；失败会把原因显示出来）。
  final ComicImageCache cache;

  /// 离线库：下载过的书断网也要有封面。
  final ComicOfflineStore offline;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final book = entry.book;
    final percent = entry.percent;
    final onlineLabel = entry.onlineLabel;
    final newChapters = entry.newChapters;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (book.isOnline && (book.coverPath ?? '').isNotEmpty)
                    ComicCoverImage(
                      url: book.coverPath!,
                      cache: cache,
                      offline: offline,
                      offlineBookUrl: book.onlineUrl ?? '',
                    )
                  else if (book.coverPath != null)
                    Image.file(
                      File(book.coverPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => const Center(
                        child: Icon(Icons.broken_image, size: 48),
                      ),
                    )
                  else
                    const Center(
                      child:
                          Icon(Icons.collections_bookmark_outlined, size: 48),
                    ),
                  // 「有新话」角标（追更）：和内容页那个是同一份记录。
                  if (newChapters > 0)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          newChapters > 1 ? '新 $newChapters 话' : '有新话',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (onlineLabel != null)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          onlineLabel,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  if (percent != null)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$percent%',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                _subtitle(book, entry.progress),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(ComicBook book, ComicReaderState? progress) {
    final total = book.pageCount ?? book.pages.length;
    if (progress != null && total > 0) {
      return '读到 ${progress.currentPageIndex + 1} / $total 页';
    }
    if (total > 0) return '$total 页';
    return '未解析页数';
  }
}

class _ImportDialog extends StatelessWidget {
  const _ImportDialog({required this.store});

  final ComicLibraryStore store;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入漫画'),
      content: const Text('选择导入方式'),
      actions: [
        TextButton(
          onPressed: () async {
            final book = await ComicImporterWidget.importFile(context);
            if (book != null) {
              await store.add(book);
              if (context.mounted) Navigator.pop(context, book);
            }
          },
          child: const Text('CBZ/ZIP 文件'),
        ),
        TextButton(
          onPressed: () async {
            final book = await ComicImporterWidget.importFolder(context);
            if (book != null) {
              await store.add(book);
              if (context.mounted) Navigator.pop(context, book);
            }
          },
          child: const Text('文件夹'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

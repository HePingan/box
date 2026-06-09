import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/features/content/domain/warehouse_models.dart';
import 'package:box/novel/core/bookshelf_manager.dart';
import 'package:box/novel/pages/novel_detail_page.dart';
import 'package:box/novel/pages/novel_list_page.dart';
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

  late Future<List<WarehouseItem>> _bookFuture;
  late Future<List<WarehouseItem>> _comicFuture;
  late Future<List<WarehouseItem>> _videoFuture;
  late Future<List<WarehouseItem>> _musicFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _bookFuture = _loadBooks();
    _comicFuture = _store.load(WarehouseCategory.comics);
    _videoFuture = _store.load(WarehouseCategory.videos);
    _musicFuture = _store.load(WarehouseCategory.music);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await Future.wait([
      _bookFuture.catchError((_) => <WarehouseItem>[]),
      _comicFuture.catchError((_) => <WarehouseItem>[]),
      _videoFuture.catchError((_) => <WarehouseItem>[]),
      _musicFuture.catchError((_) => <WarehouseItem>[]),
    ]);
  }

  Future<List<WarehouseItem>> _loadBooks() async {
    final books = await BookshelfManager.getBookshelf();
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
    return _mergeItems(liveItems, storedItems);
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
      final dynamic value = (target as dynamic)
          .toJson()
          .cast<String, dynamic>()[field];
      if (value == null) return fallback;
      final text = value.toString().trim();
      return text.isEmpty ? fallback : text;
    } catch (_) {
      try {
        final dynamic value = (target as dynamic)
            .toMap()
            .cast<String, dynamic>()[field];
        if (value == null) return fallback;
        final text = value.toString().trim();
        return text.isEmpty ? fallback : text;
      } catch (_) {
        try {
          final dynamic value = (target as dynamic).__getattribute__(field);
          if (value == null) return fallback;
          final text = value.toString().trim();
          return text.isEmpty ? fallback : text;
        } catch (_) {
          try {
            final dynamic value = (target as dynamic)[field];
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
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
              width: 420,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: '名称',
                          hintText: '请输入标题',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请输入标题';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: subtitleController,
                        decoration: const InputDecoration(
                          labelText: '副标题',
                          hintText: '作者 / 分类 / 导演 / 艺人',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: coverController,
                        decoration: const InputDecoration(
                          labelText: '封面地址',
                          hintText: 'https://...',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: detailController,
                        decoration: const InputDecoration(
                          labelText: '详情链接',
                          hintText: '可选',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: metaController,
                        decoration: const InputDecoration(
                          labelText: '备注',
                          hintText: '可填写简介、状态等信息',
                        ),
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
                setState(_reload);
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

  Future<void> _openItem(WarehouseItem item) async {
    if (item.category == WarehouseCategory.books && item.raw != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NovelDetailPage(entryBook: item.raw)),
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
                          setState(_reload);
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

  void _showHubComingSoon(String title) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$title 会在下方分区持续收纳')));
  }

  Future<List<List<WarehouseItem>>> _overviewFuture() {
    return Future.wait([
      _bookFuture.catchError((_) => <WarehouseItem>[]),
      _comicFuture.catchError((_) => <WarehouseItem>[]),
      _videoFuture.catchError((_) => <WarehouseItem>[]),
      _musicFuture.catchError((_) => <WarehouseItem>[]),
    ]);
  }

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

    if (category != null) {
      await _showAddDialog(category);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7FB),
        body: SafeArea(
          top: true,
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(
                16,
                14,
                16,
                AppTokens.pageBottomPadding + 32,
              ),
              children: [
                ContentHubTopCard(onRefresh: _refresh),
                const SizedBox(height: 16),
                ContentEntryGrid(
                  onOpenVideoCenter: _openVideoCenter,
                  onOpenNovelLibrary: _openNovelLibrary,
                  onHubComingSoon: _showHubComingSoon,
                ),
                const SizedBox(height: 18),
                ContentOverviewCard(
                  future: _overviewFuture(),
                  onOpenItem: _openItem,
                  onShowCategoryPicker: _showCategoryPicker,
                ),
                const SizedBox(height: 18),
                const WarehouseSectionHeader(
                  title: '收藏库',
                  subtitle: '我的书架 / 影视收藏 / 漫画收藏 / 音乐收藏',
                ),
                const SizedBox(height: 10),
                WarehouseSection(
                  category: WarehouseCategory.books,
                  future: _bookFuture,
                  emptyText: '从小说书架同步最近阅读，也可以手动收藏书籍链接',
                  onAdd: _showAddDialog,
                  onOpenItem: _openItem,
                  onOpenVideoCenter: _openVideoCenter,
                  onOpenNovelLibrary: _openNovelLibrary,
                ),
                const SizedBox(height: 12),
                WarehouseSection(
                  category: WarehouseCategory.comics,
                  future: _comicFuture,
                  emptyText: '漫画资源会集中放在这里，方便后续扩展漫画入口',
                  onAdd: _showAddDialog,
                  onOpenItem: _openItem,
                  onOpenVideoCenter: _openVideoCenter,
                  onOpenNovelLibrary: _openNovelLibrary,
                ),
                const SizedBox(height: 12),
                WarehouseSection(
                  category: WarehouseCategory.videos,
                  future: _videoFuture,
                  emptyText: '先去影视搜索发现内容，后续播放历史和收藏会聚合到这里',
                  onAdd: _showAddDialog,
                  onOpenItem: _openItem,
                  onOpenVideoCenter: _openVideoCenter,
                  onOpenNovelLibrary: _openNovelLibrary,
                ),
                const SizedBox(height: 12),
                WarehouseSection(
                  category: WarehouseCategory.music,
                  future: _musicFuture,
                  emptyText: '音乐链接、歌单和历史记录会集中收纳到这里',
                  onAdd: _showAddDialog,
                  onOpenItem: _openItem,
                  onOpenVideoCenter: _openVideoCenter,
                  onOpenNovelLibrary: _openNovelLibrary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

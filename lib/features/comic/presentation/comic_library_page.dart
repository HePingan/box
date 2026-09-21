import 'dart:io';

import 'package:flutter/material.dart';

import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/domain/comic_reader_state.dart';
import 'package:box/features/comic/infrastructure/comic_importer_widget.dart';
import 'package:box/features/comic/presentation/comic_reader_page.dart';

/// 书架一行的展示数据：漫画本体 + 它的真实阅读进度（没读过就是 null）。
class _ShelfEntry {
  const _ShelfEntry({required this.book, this.progress});

  final ComicBook book;
  final ComicReaderState? progress;

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
  const ComicLibraryPage({super.key, this.libraryStore});

  /// 可注入存储（测试用）；生产省略即走默认实例。
  final ComicLibraryStore? libraryStore;

  @override
  State<ComicLibraryPage> createState() => _ComicLibraryPageState();
}

class _ComicLibraryPageState extends State<ComicLibraryPage> {
  late final ComicLibraryStore _store;
  late Future<List<_ShelfEntry>> _future;

  @override
  void initState() {
    super.initState();
    _store = widget.libraryStore ?? ComicLibraryStore();
    _future = _load();
  }

  Future<List<_ShelfEntry>> _load() async {
    final books = await _store.fetch();
    final entries = <_ShelfEntry>[];
    for (final book in books) {
      entries.add(
        _ShelfEntry(book: book, progress: await _store.loadProgress(book.id)),
      );
    }
    return entries;
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
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('漫画收藏'),
        actions: [
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
              '支持导入本地 CBZ / ZIP 文件或图片文件夹。\n在线漫画源请到扩展页安装。',
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
    required this.onTap,
    required this.onDelete,
  });

  final _ShelfEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final book = entry.book;
    final percent = entry.percent;

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
                  if (book.coverPath != null)
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

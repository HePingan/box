// 离线下载管理：下过哪几本、每本占多大、每话进度、暂停/继续/删掉、一键清空。
//
// 为什么单独一页（而不是塞进漫画页里）：用户问"离线下载在哪、下了多少"的时候，
// 他要的是**一个能一眼看完的地方**；进度也不该只在某一本书的目录里才看得见。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/comic_offline_downloader.dart';
import '../domain/comic_offline_store.dart';
import '../domain/comic_online_service.dart';
import 'comic_cover_image.dart';
import 'comic_offline_wiring.dart';
import 'comic_online_page.dart' show ChapterOfflineAction;

class ComicOfflinePage extends StatefulWidget {
  const ComicOfflinePage({super.key, this.store, this.downloader});

  /// 可注入（测试用）；生产用默认实例（与漫画页共用同一份队列）。
  final ComicOfflineStore? store;
  final ComicOfflineDownloader? downloader;

  @override
  State<ComicOfflinePage> createState() => _ComicOfflinePageState();
}

class _ComicOfflinePageState extends State<ComicOfflinePage> {
  late final ComicOfflineStore _store = widget.store ?? ComicOfflineStore();
  late final ComicOfflineDownloader _downloader =
      widget.downloader ?? ComicOfflineDownloader.shared();

  List<ComicOfflineBook> _books = const <ComicOfflineBook>[];
  int _totalBytes = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _downloader.addListener(_onChanged);
    wireComicOfflineNetworkGuard(_downloader);
    unawaited(_boot());
  }

  @override
  void dispose() {
    _downloader.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _boot() async {
    // 先把"上次下到一半就没了"的任务变成可见的暂停（不会自己开始下）。
    await _downloader.loadInterrupted();
    await _reload();
  }

  Future<void> _reload() async {
    final books = await _store.books();
    final bytes = await _store.totalBytes();
    if (!mounted) return;
    setState(() {
      _books = books;
      _totalBytes = bytes;
      _loading = false;
    });
  }

  /// `done` 可能大于 `total`：崩溃 / 被杀掉之后，清单里记的是"上次以为下完的张数"，
  /// 而磁盘上可能根本没有那些图（续下会重新数）。显示成"3/2 张"就是胡说，
  /// 用户看到只会觉得"进度条又坏了"。这里只压显示，不改计数。
  static int _clampDone(int done, int total) =>
      (done > total && total > 0) ? total : done;

  static String _mb(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空离线内容？'),
        content: Text(
          '本机下载的漫画会全部删掉（共 ${_mb(_totalBytes)}），'
          '以后再读要重新联网下载。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('不清'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _store.clearAll();
    await _reload();
  }

  Future<void> _confirmDeleteBook(ComicOfflineBook book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这本书的离线内容？'),
        content: Text(
          '${book.title.isEmpty ? book.bookUrl : book.title}\n'
          '（${_mb(book.bytes)}）',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('不删'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _store.deleteBook(book.bookUrl);
    await _reload();
  }

  /// 还能继续的任务数（暂停 / 失败）。按钮的显隐与文案都用它。
  int get _resumable => _downloader.jobs
      .where(
        (j) =>
            j.state == ComicOfflineJobState.paused ||
            j.state == ComicOfflineJobState.failed,
      )
      .length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('离线下载')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '还没有下载过漫画。\n在漫画详情页点「下载」就能选下载范围。',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                if (_downloader.waitingForWifi) _wifiBanner(),
                Expanded(
                  child: ListView.builder(
                    itemCount: _books.length,
                    itemBuilder: (context, i) => _bookCard(_books[i]),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _books.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(child: Text('离线内容共 ${_mb(_totalBytes)}')),
                    // 「继续全部」：中断的任务（重启、或"只在 Wi-Fi"拦下）一话一话点太累了。
                    // 只在真有可继续的任务时出现 —— 平时别占位置。
                    if (_resumable > 0)
                      TextButton.icon(
                        onPressed: () => _downloader.resumeAll(),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text('继续全部（$_resumable）'),
                      ),
                    TextButton.icon(
                      onPressed: _confirmClearAll,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      label: const Text('清空'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// 一话的说明文字。
  ///
  /// `0/0 张` 要避免：那是"**还没开始**"（图地址还没取），写成 `0/0 张` 看着像下不动。
  String _chapterSubtitle(ComicOfflineChapter c) {
    if (c.isDone) return '已下载 ${_mb(c.bytes)}';
    if (c.state == ComicOfflineState.failed) {
      return '下载失败：${c.error}（点右边可重试）';
    }
    if (c.total == 0) {
      if (c.error.contains('Wi-Fi')) return '还没开始（按设置只在 Wi-Fi 下下载）';
      return c.state == ComicOfflineState.paused ? '已暂停' : '准备下载…';
    }
    final progress = '${_clampDone(c.done, c.total)}/${c.total} 张';
    return c.state == ComicOfflineState.paused
        ? '已暂停（$progress）'
        : '下载中（$progress）';
  }

  /// 有任务在等 Wi-Fi：给一句说明 + 一次性放行（不然用户只看到"怎么不动"）。
  Widget _wifiBanner() => Material(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 18),
          const SizedBox(width: 8),
          const Expanded(child: Text('按设置：只在 Wi-Fi 下下载（有任务在等）')),
          TextButton(
            onPressed: _downloader.allowNetworkOnce,
            child: const Text('这次用流量'),
          ),
        ],
      ),
    ),
  );

  Widget _bookCard(ComicOfflineBook book) {
    final chapters = book.chapters
        .where((c) => c.state != ComicOfflineState.none)
        .toList();
    final running = _downloader
        .jobsOfBook(book.bookUrl)
        .where((j) => j.state == ComicOfflineJobState.running);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 44,
                  height: 58,
                  child: book.cover.isEmpty
                      ? const ColoredBox(color: Color(0x11000000))
                      : ComicCoverImage(
                          url: book.cover,
                          offline: _store,
                          offlineBookUrl: book.bookUrl,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title.isEmpty ? book.bookUrl : book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '已下载 ${book.doneCount}/${chapters.length} 话 · ${_mb(book.bytes)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '删除这本书的离线内容',
                  onPressed: () => _confirmDeleteBook(book),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (running.isNotEmpty)
              for (final j in running)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '正在下载：${j.chapterTitle}（${_clampDone(j.done, j.total)}/${j.total} 张）',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: j.total > 0 ? j.progress : null,
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 4),
            for (final c in chapters)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  c.title.isEmpty ? c.url : c.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _chapterSubtitle(c),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: ChapterOfflineAction(
                  downloader: _downloader,
                  store: _store,
                  bookUrl: book.bookUrl,
                  bookTitle: book.title,
                  cover: book.cover,
                  chapter: ComicChapterRef(title: c.title, url: c.url),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

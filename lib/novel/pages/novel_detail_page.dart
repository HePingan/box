import 'package:flutter/material.dart';

import '../core/models.dart';
import '../novel_module.dart';
import 'reader_page.dart';
import '../core/bookshelf_manager.dart'; 

class NovelDetailPage extends StatefulWidget {
  const NovelDetailPage({
    super.key,
    required this.entryBook,
  });

  final NovelBook entryBook;

  @override
  State<NovelDetailPage> createState() => _NovelDetailPageState();
}

class _NovelDetailPageState extends State<NovelDetailPage> {
  bool _loading = true;
  String _error = '';
  bool _reverse = false;
  bool _inBookshelf = false; 

  NovelDetail? _detail;
  ReadingProgress? _progress;

  // 👉 缓存控制专用变量
  bool _isCaching = false;
  bool _cancelCache = false;
  int _cacheCurrent = 0;
  int _cacheTotal = 0;

  @override
  void initState() {
    super.initState();
    _load(forceRefresh: false);
  }

  @override
  void dispose() {
    _cancelCache = true; // 退出页面时自动切断后台缓存队列
    super.dispose();
  }

  NovelBook _mergeBook(NovelBook base, NovelBook remote) {
    String pick(String local, String server) => server.trim().isNotEmpty ? server : local;
    return base.copyWith(
      title: pick(base.title, remote.title),
      author: pick(base.author, remote.author),
      intro: pick(base.intro, remote.intro),
      coverUrl: pick(base.coverUrl, remote.coverUrl),
      detailUrl: pick(base.detailUrl, remote.detailUrl),
      category: pick(base.category, remote.category),
      status: pick(base.status, remote.status),
      wordCount: pick(base.wordCount, remote.wordCount),
    );
  }

  Future<void> _load({required bool forceRefresh}) async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final detail = await NovelModule.repository.fetchDetail(
        bookId: widget.entryBook.id,
        detailUrl: widget.entryBook.detailUrl,
        forceRefresh: forceRefresh,
      );

      final merged = NovelDetail(
        book: _mergeBook(widget.entryBook, detail.book),
        chapters: detail.chapters,
      );
      
      final progress = await NovelModule.repository.getProgress(merged.book.id);
      final inShelf = await BookshelfManager.isInBookshelf(merged.book.id); 

      if (!mounted) return;
      setState(() {
        _detail = merged;
        _progress = progress;
        _inBookshelf = inShelf;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '详情加载失败：$e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // 加书架逻辑
  Future<void> _toggleBookshelf() async {
    final bookToSave = _detail?.book ?? widget.entryBook;
    if (_inBookshelf) {
      await BookshelfManager.removeFromBookshelf(bookToSave.id);
      if (mounted) {
        setState(() => _inBookshelf = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已移出书架')));
      }
    } else {
      await BookshelfManager.addToBookshelf(bookToSave);
      if (mounted) {
        setState(() => _inBookshelf = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📚 成功加入书架！')));
      }
    }
  }

  // 👉 核心：全本缓存队列控制
  Future<void> _toggleCache() async {
    // 1. 如果正在缓存，点击则暂停
    if (_isCaching) {
      setState(() {
        _cancelCache = true;
        _isCaching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已暂停缓存')));
      return;
    }

    final detail = _detail;
    if (detail == null || detail.chapters.isEmpty) return;

    // 2. 准备开始下载
    setState(() {
      _isCaching = true;
      _cancelCache = false;
      _cacheTotal = detail.chapters.length;
      _cacheCurrent = 0;
    });

    // 为了防止未缓存就退出，直接自动加书架
    if (!_inBookshelf) _toggleBookshelf();

    // 3. 开始智能循环拉取
    for (int i = 0; i < detail.chapters.length; i++) {
      if (_cancelCache || !mounted) break; // 用户退出或者点了暂停立刻中断
      
      try {
        // 调用你系统中原有的 fetchChapter。forceRefresh 为 false 表示：如果库里有就瞬间跳过，贼快！
        await NovelModule.repository.fetchChapter(
          detail: detail,
          chapterIndex: i,
          forceRefresh: false, 
        );
      } catch (_) {
        // 忽略单章网络错误，让剩余继续下
      }

      if (mounted) {
        setState(() => _cacheCurrent = i + 1);
      }
    }

    // 4. 下载完成收尾
    if (mounted && !_cancelCache) {
      setState(() => _isCaching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🎉 全本缓存完成，断网可看！')),
      );
    }
  }

  void _openReader(int chapterIndex) {
    final detail = _detail;
    if (detail == null || detail.chapters.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderPage(detail: detail, initialChapterIndex: chapterIndex)),
    ).then((_) async {
      final p = await NovelModule.repository.getProgress(detail.book.id);
      if (!mounted) return;
      setState(() => _progress = p);
    });
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('小说详情', style: TextStyle(color: Colors.black)),
        backgroundColor: const Color(0xFFF7F8FA),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: Icon(_inBookshelf ? Icons.favorite : Icons.favorite_border),
            color: _inBookshelf ? Colors.redAccent : Colors.black54,
            onPressed: _loading ? null : _toggleBookshelf,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _load(forceRefresh: true)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error, style: const TextStyle(color: Colors.redAccent))))
              : detail == null
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                               ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  detail.book.coverUrl, width: 96, height: 132, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(width: 96, height: 132, color: Colors.grey[200], child: const Icon(Icons.menu_book, color: Colors.black38)),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(detail.book.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8, runSpacing: 8,
                                      children: [
                                        _tag(detail.book.author, Colors.teal),
                                        if (detail.book.category.isNotEmpty) _tag(detail.book.category, Colors.orange),
                                        if (detail.book.status.isNotEmpty) _tag(detail.book.status, Colors.blue),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(detail.book.intro.isEmpty ? '暂无简介' : detail.book.intro, style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.45), maxLines: 4, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // 👉 三重操作按钮：排布更为均匀紧凑
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: ElevatedButton(
                                  onPressed: detail.chapters.isEmpty ? null : () => _openReader(_progress?.chapterIndex ?? 0),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700]), // 用醒目的蓝色
                                  child: Text(_progress == null ? '开始阅读' : '继续阅读', style: const TextStyle(color: Colors.white)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: OutlinedButton(
                                  onPressed: _toggleBookshelf,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _inBookshelf ? Colors.grey[600] : Colors.teal,
                                    side: BorderSide(color: _inBookshelf ? Colors.grey[400]! : Colors.teal),
                                  ),
                                  child: Text(_inBookshelf ? '已加书架' : '+ 加书架'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: OutlinedButton(
                                  onPressed: _toggleCache,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _isCaching ? Colors.orange : Colors.blueGrey,
                                    side: BorderSide(color: _isCaching ? Colors.orange : Colors.blueGrey),
                                  ),
                                  // 下载时按钮变色、变成停止
                                  child: Text(_isCaching ? '暂停下载' : '缓存全本'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // 👉 智能进度条与章节翻转控制区
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: _isCaching 
                                  // 如果正在缓存：显示酷炫拉伸进度条
                                  ? Row(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: _cacheTotal == 0 ? 0 : (_cacheCurrent / _cacheTotal),
                                              minHeight: 6,
                                              backgroundColor: Colors.grey[300],
                                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text('$_cacheCurrent/$_cacheTotal', style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold)),
                                      ],
                                    )
                                  // 如果没缓存：正常显示上次阅读历史
                                  : Text(
                                      _progress != null ? '上次读到：${_progress!.chapterTitle}' : '历史提示：暂无阅读记录',
                                      style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              ),
                              const SizedBox(width: 16),
                              InkWell(
                                onTap: () => setState(() => _reverse = !_reverse),
                                child: Row(
                                  children: [
                                    Icon(_reverse ? Icons.vertical_align_top : Icons.vertical_align_bottom, size: 16, color: Colors.black54),
                                    const SizedBox(width: 2),
                                    Text(_reverse ? '正序' : '倒序', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const Divider(height: 1),
                        // 章节列表
                        Expanded(
                          child: ListView.separated(
                            itemCount: detail.chapters.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final actual = _reverse ? detail.chapters.length - 1 - index : index;
                              final chapter = detail.chapters[actual];
                              final selected = _progress != null && _progress!.chapterIndex == actual;

                              return ListTile(
                                selected: selected,
                                selectedTileColor: Colors.teal.withOpacity(0.08),
                                title: Text(
                                  chapter.title,
                                  style: TextStyle(color: selected ? Colors.teal : Colors.black87, fontWeight: selected ? FontWeight.bold : FontWeight.normal),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                                onTap: () => _openReader(actual),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }
}
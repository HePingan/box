import 'package:flutter/material.dart';
import '../core/models.dart';
import '../novel_module.dart';
import 'reader_page.dart';
import '../core/bookshelf_manager.dart';

class NovelDetailPage extends StatefulWidget {
  const NovelDetailPage({super.key, required this.entryBook});
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
    _cancelCache = true;
    super.dispose();
  }

  Future<void> _load({required bool forceRefresh}) async {
    setState(() { _loading = true; _error = ''; });
    try {
      final detail = await NovelModule.repository.fetchDetail(
        bookId: widget.entryBook.id, 
        detailUrl: widget.entryBook.detailUrl, 
        forceRefresh: forceRefresh,
      );
      
      final newBook = detail.book;
      final merged = NovelDetail(
        book: widget.entryBook.copyWith(
          title: newBook.title.isNotEmpty ? newBook.title : null,
          author: newBook.author.isNotEmpty ? newBook.author : null,
          intro: newBook.intro.isNotEmpty ? newBook.intro : null,
          coverUrl: newBook.coverUrl.isNotEmpty ? newBook.coverUrl : null,
          category: newBook.category.isNotEmpty ? newBook.category : null, 
          status: newBook.status.isNotEmpty ? newBook.status : null,
          wordCount: newBook.wordCount.isNotEmpty ? newBook.wordCount : null,
        ),
        chapters: detail.chapters,
      );
      
      final progress = await NovelModule.repository.getProgress(merged.book.id);
      final inShelf = await BookshelfManager.isInBookshelf(merged.book.id);
      
      if (mounted) {
        setState(() { 
          _detail = merged; 
          _progress = progress; 
          _inBookshelf = inShelf; 
          _loading = false;
        });
      }

      // 如果合并后的数据依然没有简介，立刻启动静默搜索去补全它！
      if (merged.book.intro.trim().isEmpty) {
        _silentPatchMissingMetadata(merged.book.title, merged.book.author);
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载失败：$e';
          _loading = false;
        });
      }
    }
  }

  // 💡 无感后台修补方法
  Future<void> _silentPatchMissingMetadata(String title, String author) async {
    if (title.isEmpty) return;
    try {
      final searchResults = await NovelModule.repository.searchBooks(title, page: 1, forceRefresh: true);
      
      NovelBook? exactBook;
      for (var book in searchResults) {
        if (book.title == title) {
          exactBook = book;
          break;
        }
      }

      // 💡 加上 ! 叹号告诉编译器，我已经确认它绝对不为 null 了
      if (exactBook != null && exactBook.intro.isNotEmpty && mounted && _detail != null) {
        setState(() {
          _detail = NovelDetail(
            book: _detail!.book.copyWith(
              intro: exactBook!.intro,  
              category: exactBook!.category.isNotEmpty ? exactBook!.category : null,
              status: exactBook!.status.isNotEmpty ? exactBook!.status : null,
              wordCount: exactBook!.wordCount.isNotEmpty ? exactBook!.wordCount : null,
            ),
            chapters: _detail!.chapters, 
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleBookshelf() async {
    final bookToSave = _detail?.book ?? widget.entryBook;
    if (_inBookshelf) {
      await BookshelfManager.removeFromBookshelf(bookToSave.id);
      if (mounted) setState(() => _inBookshelf = false);
    } else {
      await BookshelfManager.addToBookshelf(bookToSave);
      if (mounted) setState(() => _inBookshelf = true);
    }
  }

  Future<void> _toggleCache() async {
    if (_isCaching) {
      setState(() { _cancelCache = true; _isCaching = false; });
      return;
    }
    
    final detail = _detail;
    if (detail == null || detail.chapters.isEmpty) return;

    setState(() {
      _isCaching = true; 
      _cancelCache = false;
      _cacheTotal = detail.chapters.length; 
      _cacheCurrent = 0;
    });

    if (!_inBookshelf) _toggleBookshelf();

    for (int i = 0; i < detail.chapters.length; i++) {
      if (_cancelCache || !mounted) break;
      try {
        await NovelModule.repository.fetchChapter(detail: detail, chapterIndex: i, forceRefresh: false);
      } catch (_) {}
      
      if (i % 10 == 0) await Future.delayed(const Duration(milliseconds: 20));
      if (mounted) setState(() => _cacheCurrent = i + 1);
    }
    
    if (mounted && !_cancelCache) setState(() => _isCaching = false);
  }

  void _openReader(int chapterIndex) {
    if (_detail == null || _detail!.chapters.isEmpty) return;
    Navigator.push(
      context, 
      MaterialPageRoute(builder: (_) => ReaderPage(detail: _detail!, initialChapterIndex: chapterIndex))
    ).then((_) async {
      final p = await NovelModule.repository.getProgress(_detail!.book.id);
      if (mounted) setState(() => _progress = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_detail == null) return Scaffold(body: Center(child: Text(_error)));
    
    final book = _detail!.book;
    final chaps = _detail!.chapters;

    final metaTags = <String>[];
    if (book.author.isNotEmpty) metaTags.add(book.author);
    if (book.category.isNotEmpty) metaTags.add(book.category);
    if (book.status.isNotEmpty) metaTags.add(book.status);
    if (book.wordCount.isNotEmpty) metaTags.add(book.wordCount);
    final metaString = metaTags.join(' · ');
    
    final displayIntro = book.intro.isNotEmpty 
        ? book.intro 
        : '正在全网匹配简介与信息...'; 

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('小说详情', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.transparent, 
        elevation: 0, 
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _load(forceRefresh: true)),
        ],
      ),
      body: Column(
        children: [
          // 1. 书籍信息头部
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10), 
                  child: Image.network(
                    book.coverUrl, 
                    width: 80, height: 110, fit: BoxFit.cover, 
                    errorBuilder: (_,__,___) => Container(width:80, height:110, color:Colors.grey[300])
                  )
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(book.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(metaString.isNotEmpty ? metaString : '分类与进度数据装载中', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                      const SizedBox(height: 8),
                      Text(
                        displayIntro, 
                        maxLines: 4, 
                        overflow: TextOverflow.ellipsis, 
                        style: TextStyle(
                           fontSize: 13, 
                           height: 1.4,
                           color: book.intro.isNotEmpty ? Colors.black87 : Colors.blueGrey, 
                        )
                      ),
                    ],
                  )
                ),
              ],
            ),
          ),
          
          // 2. 操作按钮组
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  flex: 12, 
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ), 
                    onPressed: chaps.isEmpty ? null : () => _openReader(_progress?.chapterIndex ?? 0), 
                    child: Text(_progress == null ? '开始阅读' : '继续阅读', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                  )
                ), 
                const SizedBox(width: 8),
                Expanded(
                  flex: 10, 
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _inBookshelf ? Colors.grey : Colors.blue[600],
                      side: BorderSide(color: _inBookshelf ? Colors.grey[300]! : Colors.blue[600]!),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _loading ? null : _toggleBookshelf, 
                    child: Text(_inBookshelf ? '移出书架' : '+ 加书架')
                  )
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 10, 
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _isCaching ? Colors.orange : Colors.blueGrey,
                      side: BorderSide(color: _isCaching ? Colors.orange : Colors.blueGrey),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _toggleCache, 
                    child: Text(_isCaching ? '暂停下载' : '缓存全本')
                  )
                ),
              ],
            ),
          ),
          
          // 3. 阅读历史/顺倒序
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: _isCaching 
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
                    : Text(
                        _progress != null ? '上次读到：${_progress!.chapterTitle}' : '共 ${chaps.length} 章',
                        style: const TextStyle(fontSize: 13, color: Colors.black54),
                        overflow: TextOverflow.ellipsis,
                      ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => setState(() => _reverse = !_reverse),
                  child: Row(
                    children: [
                      Icon(
                        _reverse ? Icons.vertical_align_top : Icons.vertical_align_bottom, 
                        size: 16, 
                        color: Colors.black54
                      ),
                      const SizedBox(width: 2),
                      Text(_reverse ? '正序' : '倒序', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // 4. 章节列表
          Expanded(
            child: ListView.builder(
              itemCount: chaps.length,
              itemBuilder: (ctx, i) {
                final index = _reverse ? chaps.length - 1 - i : i;
                final cur = _progress?.chapterIndex == index;
                return ListTile(
                  title: Text(
                    chaps[index].title, 
                    maxLines: 1, 
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cur ? Colors.blue[600] : Colors.black87, 
                      fontWeight: cur ? FontWeight.bold : FontWeight.normal
                    )
                  ),
                  onTap: () => _openReader(index),
                );
              },
            )
          ),
        ],
      ),
    );
  }
}
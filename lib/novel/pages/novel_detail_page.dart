import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/novel_detail_controller.dart';
import '../core/models.dart';
import 'reader_page.dart';

class NovelDetailPage extends StatefulWidget {
  const NovelDetailPage({super.key, required this.entryBook});
  final NovelBook entryBook;

  @override
  State<NovelDetailPage> createState() => _NovelDetailPageState();
}

class _NovelDetailPageState extends State<NovelDetailPage> {
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NovelDetailController>();
    final detail = controller.detail;

    if (controller.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (detail == null) {
      return Scaffold(body: Center(child: Text(controller.error)));
    }

    final book = detail.book;
    final chaps = detail.chapters;

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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => controller.reload(forceRefresh: true),
          ),
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
                    width: 80,
                    height: 110,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(width: 80, height: 110, color: Colors.grey[300]),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        metaString.isNotEmpty ? metaString : '分类与进度数据装载中',
                        style: const TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        displayIntro,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: book.intro.isNotEmpty ? Colors.black87 : Colors.blueGrey,
                        ),
                      ),
                    ],
                  ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: chaps.isEmpty
                        ? null
                        : () => _openReader(
                              context,
                              controller.progress?.chapterIndex ?? 0,
                            ),
                    child: Text(
                      controller.progress == null ? '开始阅读' : '继续阅读',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 10,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          controller.inBookshelf ? Colors.grey : Colors.blue[600],
                      side: BorderSide(
                        color: controller.inBookshelf
                            ? Colors.grey[300]!
                            : Colors.blue[600]!,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: controller.loading ? null : controller.toggleBookshelf,
                    child: Text(controller.inBookshelf ? '移出书架' : '+ 加书架'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 10,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          controller.isCaching ? Colors.orange : Colors.blueGrey,
                      side: BorderSide(
                        color: controller.isCaching ? Colors.orange : Colors.blueGrey,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: controller.toggleCache,
                    child: Text(controller.isCaching ? '暂停下载' : '缓存全本'),
                  ),
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
                  child: controller.isCaching
                      ? Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: controller.cacheTotal == 0
                                      ? 0
                                      : (controller.cacheCurrent / controller.cacheTotal),
                                  minHeight: 6,
                                  backgroundColor: Colors.grey[300],
                                  valueColor: const AlwaysStoppedAnimation<Color>(
                                    Colors.orange,
                                  ),
                                ),
                              ),
                            ),
                              const SizedBox(width: 10),
                              Text(
                                '${controller.cacheCurrent}/${controller.cacheTotal}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        )
                      : Text(
                          controller.progress != null
                              ? '上次读到：${controller.progress!.chapterTitle}'
                              : '共 ${chaps.length} 章',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => controller.toggleReverse(),
                  child: Row(
                    children: [
                      Icon(
                        controller.reverse
                            ? Icons.vertical_align_top
                            : Icons.vertical_align_bottom,
                        size: 16,
                        color: Colors.black54,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        controller.reverse ? '正序' : '倒序',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
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
                final index = controller.reverse
                    ? chaps.length - 1 - i
                    : i;
                final cur = controller.progress?.chapterIndex == index;
                return ListTile(
                  title: Text(
                    chaps[index].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cur ? Colors.blue[600] : Colors.black87,
                      fontWeight: cur ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  onTap: () => _openReader(context, index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openReader(BuildContext context, int chapterIndex) {
    final controller = context.read<NovelDetailController>();
    final detail = controller.detail;
    if (detail == null || detail.chapters.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderPage(
          detail: detail,
          initialChapterIndex: chapterIndex,
        ),
      ),
    ).then((_) async {
      await controller.refreshProgress();
    });
  }
}

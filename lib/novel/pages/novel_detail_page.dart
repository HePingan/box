import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/novel_detail_controller.dart';
import '../core/models.dart';
import 'reader_page.dart';
import '../../design_system/app_tokens.dart';

class NovelDetailPage extends StatefulWidget {
  const NovelDetailPage({super.key, required this.entryBook});
  final NovelBook entryBook;

  @override
  State<NovelDetailPage> createState() => _NovelDetailPageState();
}

class _NovelDetailPageState extends State<NovelDetailPage> {
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
    final displayIntro = book.intro.isNotEmpty ? book.intro : '正在全网匹配简介与信息...';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F3FF),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 292,
            pinned: true,
            backgroundColor: const Color(0xFF2E1065),
            foregroundColor: Colors.white,
            title: const Text('小说详情'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => controller.reload(forceRefresh: true),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildDetailHero(book, metaString, displayIntro),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: _buildActionPanel(controller, chaps),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _buildProgressPanel(controller, chaps),
            ),
          ),
          SliverToBoxAdapter(child: _buildChapterHeader(controller)),
          SliverList.builder(
            itemCount: chaps.length,
            itemBuilder: (ctx, i) {
              final index = controller.reverse ? chaps.length - 1 - i : i;
              final cur = controller.progress?.chapterIndex == index;
              return Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                decoration: BoxDecoration(
                  color: cur ? const Color(0xFFF3E8FF) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cur
                        ? const Color(0xFFC084FC)
                        : const Color(0xFFEDE9FE),
                  ),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: cur
                        ? const Color(0xFF7C3AED)
                        : const Color(0xFFF1F5F9),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: cur ? Colors.white : const Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  title: Text(
                    chaps[index].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cur ? const Color(0xFF6D28D9) : AppTokens.inkDark,
                      fontWeight: cur ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openReader(context, index),
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  Widget _buildDetailHero(
    NovelBook book,
    String metaString,
    String displayIntro,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2E1065), Color(0xFF7C3AED), Color(0xFFF59E0B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 92, 18, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.network(
                  book.coverUrl,
                  width: 96,
                  height: 136,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 96,
                    height: 136,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.auto_stories_rounded,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BOOK DETAIL · 新版',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      metaString.isNotEmpty ? metaString : '分类与进度数据装载中',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      displayIntro,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionPanel(
    NovelDetailController controller,
    List<NovelChapter> chaps,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEDE9FE)),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: chaps.isEmpty
                  ? null
                  : () => _openReader(
                      context,
                      controller.progress?.chapterIndex ?? 0,
                    ),
              icon: const Icon(Icons.chrome_reader_mode_rounded),
              label: Text(controller.progress == null ? '开始阅读' : '继续阅读'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: controller.loading ? null : controller.toggleBookshelf,
            child: Text(controller.inBookshelf ? '移出书架' : '+ 书架'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: controller.toggleCache,
            child: Text(controller.isCaching ? '暂停' : '缓存'),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressPanel(
    NovelDetailController controller,
    List<NovelChapter> chaps,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEDE9FE)),
      ),
      child: controller.isCaching
          ? Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: controller.cacheTotal == 0
                        ? 0
                        : (controller.cacheCurrent / controller.cacheTotal),
                    minHeight: 7,
                    color: const Color(0xFFF59E0B),
                    backgroundColor: const Color(0xFFFFEDD5),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${controller.cacheCurrent}/${controller.cacheTotal}',
                  style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            )
          : Text(
              controller.progress != null
                  ? '上次读到：${controller.progress!.chapterTitle}'
                  : '共 ${chaps.length} 章 · 可加入书架后继续追更',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }

  Widget _buildChapterHeader(NovelDetailController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          const Text(
            '章节目录',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => controller.toggleReverse(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                border: Border.all(color: const Color(0xFFEDE9FE)),
              ),
              child: Row(
                children: [
                  Icon(
                    controller.reverse
                        ? Icons.vertical_align_top
                        : Icons.vertical_align_bottom,
                    size: 16,
                    color: const Color(0xFF7C3AED),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    controller.reverse ? '正序' : '倒序',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF7C3AED),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
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
        builder: (_) =>
            ReaderPage(detail: detail, initialChapterIndex: chapterIndex),
      ),
    ).then((_) async {
      await controller.refreshProgress();
    });
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design_system/widgets/app_back_button.dart';
import '../../design_system/widgets/empty_error_states.dart';
import '../../design_system/widgets/shimmer_skeleton.dart';
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
  bool _introExpanded = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NovelDetailController>();
    final detail = controller.detail;

    if (controller.loading) {
      return const DetailPageSkeleton();
    }
    if (detail == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF6F3FF),
        body: ErrorStateView(
          message: controller.error,
          onRetry: () => controller.reload(forceRefresh: true),
        ),
      );
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
            expandedHeight: 200,
            collapsedHeight: 56,
            pinned: true,
            stretch: true,
            backgroundColor: const Color(0xFFF6F3FF),
            surfaceTintColor: Colors.transparent,
            foregroundColor: const Color(0xFF2E1065),
            leading: AppBackButtonLight(onPressed: () => Navigator.pop(context)),
            title: Text(
              book.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 22),
                onPressed: () => controller.reload(forceRefresh: true),
                tooltip: '刷新',
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildDetailHero(book, metaString),
            ),
          ),
          // 简介 + 进度
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: _buildIntroCard(displayIntro, chaps, controller),
            ),
          ),
          // 操作栏
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: _buildActionBar(controller, chaps),
            ),
          ),
          // 章节标题
          SliverToBoxAdapter(child: _buildChapterHeader(controller)),
          // 章节列表
          SliverList.builder(
            itemCount: chaps.length,
            itemBuilder: (ctx, i) {
              final index = controller.reverse ? chaps.length - 1 - i : i;
              final cur = controller.progress?.chapterIndex == index;
              return _buildChapterItem(index, chaps[index], cur, controller);
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  Widget _buildDetailHero(NovelBook book, String metaString) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, kToolbarHeight + 8, 20, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF6F3FF), Color(0xFFEDE9FE)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      alignment: Alignment.bottomLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 124,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.10),
                width: 0.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.network(
              book.coverUrl,
              width: 88,
              height: 124,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 88,
                height: 124,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDD6FE),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: Color(0xFF7C3AED),
                  size: 36,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2E1065),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  metaString.isNotEmpty ? metaString : '数据加载中',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7C3AED),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroCard(
    String intro,
    List<NovelChapter> chaps,
    NovelDetailController controller,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDE9FE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_stories_rounded,
                size: 16,
                color: Color(0xFF7C3AED),
              ),
              const SizedBox(width: 6),
              const Text(
                '简介',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              Text(
                '${chaps.length} 章',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (ctx, constraints) {
              // 检测是否超 4 行
              const style = TextStyle(
                fontSize: 13,
                height: 1.55,
                color: Color(0xFF475569),
              );
              final span = TextSpan(text: intro, style: style);
              final tp = TextPainter(
                text: span,
                maxLines: 4,
                textDirection: TextDirection.ltr,
              );
              tp.layout(maxWidth: constraints.maxWidth);
              final isLong = tp.didExceedMaxLines;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    intro,
                    maxLines: _introExpanded ? null : 4,
                    overflow: _introExpanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: style,
                  ),
                  if (isLong)
                    GestureDetector(
                      onTap: () => setState(() => _introExpanded = !_introExpanded),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _introExpanded ? '收起' : '展开全文',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF7C3AED),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              _introExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: Color(0xFF7C3AED),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          // 阅读进度条
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  controller.progress != null
                      ? Icons.menu_book_rounded
                      : Icons.book_outlined,
                  size: 15,
                  color: const Color(0xFF7C3AED),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    controller.progress != null
                        ? '读到：${controller.progress!.chapterTitle}'
                        : '暂无阅读记录',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: controller.progress != null
                          ? const Color(0xFF475569)
                          : const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (controller.isCaching)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 52,
                        child: LinearProgressIndicator(
                          value: controller.cacheTotal == 0
                              ? 0
                              : (controller.cacheCurrent /
                                    controller.cacheTotal),
                          minHeight: 4,
                          color: const Color(0xFFF59E0B),
                          backgroundColor: const Color(0xFFFFEDD5),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${controller.cacheCurrent}/${controller.cacheTotal}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFF59E0B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(
    NovelDetailController controller,
    List<NovelChapter> chaps,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
              icon: const Icon(Icons.chrome_reader_mode_rounded, size: 18),
              label: Text(controller.progress == null ? '开始阅读' : '继续阅读'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _buildMiniButton(
            icon: controller.inBookshelf
                ? Icons.bookmark
                : Icons.bookmark_border,
            label: '书架',
            onTap: controller.loading ? null : controller.toggleBookshelf,
            active: controller.inBookshelf,
          ),
          const SizedBox(width: 6),
          _buildMiniButton(
            icon: controller.isCaching
                ? Icons.downloading
                : Icons.download_outlined,
            label: '缓存',
            onTap: controller.toggleCache,
            active: controller.isCaching,
          ),
        ],
      ),
    );
  }

  Widget _buildMiniButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool active = false,
  }) {
    return Material(
      color: active ? const Color(0xFFF3E8FF) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: active ? const Color(0xFFC084FC) : const Color(0xFFE2E8F0),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: active
                    ? const Color(0xFF7C3AED)
                    : const Color(0xFF64748B),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChapterHeader(NovelDetailController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          const Icon(
            Icons.list_alt_rounded,
            size: 18,
            color: Color(0xFF2E1065),
          ),
          const SizedBox(width: 6),
          const Text(
            '章节目录',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2E1065),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => controller.toggleReverse(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    controller.reverse
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 14,
                    color: const Color(0xFF7C3AED),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    controller.reverse ? '正序' : '倒序',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7C3AED),
                      fontWeight: FontWeight.w600,
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

  Widget _buildChapterItem(
    int index,
    NovelChapter chapter,
    bool isCurrent,
    NovelDetailController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Material(
        color: isCurrent ? const Color(0xFFF3E8FF) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openReader(context, index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? const Color(0xFF7C3AED)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isCurrent ? Colors.white : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    chapter.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isCurrent
                          ? const Color(0xFF6D28D9)
                          : const Color(0xFF334155),
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: isCurrent
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFFCBD5E1),
                ),
              ],
            ),
          ),
        ),
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

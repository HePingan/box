import 'package:flutter/material.dart';

import 'reader_controller.dart';

/// 书签列表 BottomSheet
class ReaderBookmarkSheet extends StatefulWidget {
  const ReaderBookmarkSheet({
    super.key,
    required this.controller,
    required this.bgColor,
    required this.textColor,
  });

  final ReaderController controller;
  final Color bgColor;
  final Color textColor;

  @override
  State<ReaderBookmarkSheet> createState() => _ReaderBookmarkSheetState();
}

class _ReaderBookmarkSheetState extends State<ReaderBookmarkSheet> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final bookmarks = controller.bookmarks;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Text(
                    '书签',
                    style: TextStyle(
                      color: widget.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${bookmarks.length} 条',
                    style: TextStyle(
                      color: widget.textColor.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  if (bookmarks.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('清空书签'),
                            content: const Text('确定清空本书所有书签？'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text(
                                  '取消',
                                  style: TextStyle(color: widget.textColor),
                                ),
                              ),
                              FilledButton(
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  await controller.bookmarkService
                                      .clear(controller.detail.book.id);
                                  if (!mounted) return;
                                  setState(() {});
                                },
                                child: const Text('清空'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Text(
                        '清空',
                        style: TextStyle(
                          color: widget.textColor.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: widget.textColor.withValues(alpha: 0.08),
            ),

            // 书签列表
            Expanded(
              child: bookmarks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bookmark_border_rounded,
                            size: 48,
                            color: widget.textColor.withValues(alpha: 0.25),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '暂无书签',
                            style: TextStyle(
                              color: widget.textColor.withValues(alpha: 0.45),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '长按阅读区域可添加书签',
                            style: TextStyle(
                              color: widget.textColor.withValues(alpha: 0.3),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: bookmarks.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: widget.textColor.withValues(alpha: 0.05),
                      ),
                      itemBuilder: (_, i) {
                        final bm = bookmarks[i];
                        final isCurrent =
                            bm.chapterIndex == controller.chapterIndex;

                        return InkWell(
                          onTap: () => Navigator.pop(context, bm.chapterIndex),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.bookmark_rounded,
                                  size: 20,
                                  color: isCurrent
                                      ? Colors.orange
                                      : widget.textColor
                                          .withValues(alpha: 0.4),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        bm.chapterTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isCurrent
                                              ? Colors.orange
                                              : widget.textColor,
                                          fontWeight: isCurrent
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatTime(bm.createdAt),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: widget.textColor
                                              .withValues(alpha: 0.4),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isCurrent)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange
                                          .withValues(alpha: 0.15),
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '当前',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ),
                                IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: widget.textColor
                                        .withValues(alpha: 0.35),
                                  ),
                                  onPressed: () async {
                                    await controller.removeBookmark(bm.id);
                                    if (!mounted) return;
                                    setState(() {});
                                  },
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

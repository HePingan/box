import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../design_system/app_tokens.dart';
import '../../controllers/novel_detail_controller.dart';
import '../../core/models.dart';
import '../novel_detail_page.dart';

/// 小说卡片组件
class NovelBookCard extends StatelessWidget {
  const NovelBookCard({super.key, required this.book});

  final NovelBook book;

  static Widget _buildCoverFallback({double width = 64, double height = 86}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF312E81), Color(0xFF7C3AED), Color(0xFFF59E0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.10),
          width: 0.5,
        ),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.auto_stories_rounded, color: Colors.white70),
    );
  }

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (book.author.trim().isNotEmpty) '作者 ${book.author.trim()}',
      if (book.category.trim().isNotEmpty) book.category.trim(),
      if (book.status.trim().isNotEmpty) book.status.trim(),
      if (book.wordCount.trim().isNotEmpty) book.wordCount.trim(),
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChangeNotifierProvider(
                create: (_) => NovelDetailController(entryBook: book),
                child: NovelDetailPage(entryBook: book),
              ),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFEDE9FE)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                blurRadius: 22,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              Container(
                width: 72,
                height: 96,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.10),
                    width: 0.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: book.coverUrl.isNotEmpty
                    ? Image.network(
                        book.coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildCoverFallback(),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return _buildCoverFallback();
                        },
                      )
                    : _buildCoverFallback(),
              ),
              const SizedBox(width: 14),
              // 文字信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (meta.isNotEmpty)
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTokens.textSecondary,
                        ),
                      ),
                    if (book.intro.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        book.intro,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTokens.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // 底部标签
                    Row(
                      children: [
                        _buildTag(
                          book.author.trim().isNotEmpty
                              ? book.author.trim()
                              : '未知作者',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 箭头
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: AppTokens.violet.withValues(alpha: 0.35),
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          color: AppTokens.violet,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

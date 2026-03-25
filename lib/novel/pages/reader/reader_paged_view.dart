import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'reader_controller.dart';

class ReaderPagedView extends StatelessWidget {
  const ReaderPagedView({
    super.key,
    required this.controller,
    required this.pageController,
    required this.textPages,
    required this.settings,
    required this.textColor,
    required this.topPadding,
    required this.onPageChanged,
  });

  final ReaderController controller;
  final PageController pageController;
  final List<String> textPages;
  final ReaderSettings settings;
  final Color textColor;
  final double topPadding;
  final ValueChanged<int> onPageChanged;

  Widget _buildBoundaryPage({
    required bool isNext,
  }) {
    final canMove = isNext ? controller.canGoNext : controller.canGoPrev;

    final tip = !canMove
        ? (isNext ? '已经是最后一章' : '已经是第一章')
        : (isNext ? '继续左滑进入下一章' : '继续右滑进入上一章');

    String nextTitle = '';
    if (canMove) {
      final targetIndex = isNext
          ? controller.chapterIndex + 1
          : controller.chapterIndex - 1;
      nextTitle = controller.detail.chapters[targetIndex].title;
    }

    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding + 24, 20, 24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isNext ? Icons.swipe_left_rounded : Icons.swipe_right_rounded,
            size: 34,
            color: textColor.withOpacity(0.45),
          ),
          const SizedBox(height: 10),
          Text(
            tip,
            style: TextStyle(
              fontSize: 14,
              color: textColor.withOpacity(0.72),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (nextTitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                nextTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: textColor.withOpacity(0.52),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = textPages.length;

    if (totalPages <= 0) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: textColor.withOpacity(0.4),
        ),
      );
    }

    return PageView.builder(
      controller: pageController,
      itemCount: totalPages + 2,
      onPageChanged: onPageChanged,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, viewIndex) {
        if (viewIndex == 0) {
          return _buildBoundaryPage(isNext: false);
        }

        if (viewIndex == totalPages + 1) {
          return _buildBoundaryPage(isNext: true);
        }

        final index = viewIndex - 1;

        return Container(
          padding: EdgeInsets.fromLTRB(20, topPadding + 8, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (index == 0)
                Container(
                  height: 46,
                  alignment: Alignment.bottomLeft,
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    controller.currentChapterTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      height: 1.1,
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 24,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      controller.currentChapterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: textColor.withOpacity(0.5),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  textPages[index],
                  style: TextStyle(
                    fontSize: settings.fontSize,
                    height: settings.lineHeight,
                    letterSpacing: 0.6,
                    color: textColor,
                  ),
                ),
              ),
              SizedBox(
                height: 24,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        controller.bookTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: textColor.withOpacity(0.5),
                        ),
                      ),
                    ),
                    Text(
                      '${index + 1}/$totalPages   ${((index + 1) / totalPages * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
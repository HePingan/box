import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'reader_controller.dart';
import 'reader_layout_metrics.dart';

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
    this.onLookupWord,
    this.menuVisible = false,
  });

  final ReaderController controller;
  final PageController pageController;
  final List<String> textPages;
  final ReaderSettings settings;
  final Color textColor;
  final double topPadding;
  final ValueChanged<int> onPageChanged;

  /// 查词回调（从 contextMenuBuilder -> 选中文字）
  final void Function(String word)? onLookupWord;

  /// 菜单是否可见，影响 SelectableText 是否启用选词功能
  final bool menuVisible;

  Widget _buildBoundaryPage({required bool isNext}) {
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
            color: textColor.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 10),
          Text(
            tip,
            style: TextStyle(
              fontSize: 14,
              color: textColor.withValues(alpha: 0.72),
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
                  color: textColor.withValues(alpha: 0.52),
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
          color: textColor.withValues(alpha: 0.4),
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

        return Stack(
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(20, topPadding + 8, 20, 8),
              // 小窗里可用高度可能比标题块还矮，标题必须给正文让位，
              // 否则 Expanded 拿到负高度 → 正文一个字都画不出。
              child: LayoutBuilder(
                builder: (context, box) {
                  final metrics = ReaderLayoutMetrics.resolve(
                    availableHeight: box.maxHeight,
                    isFirstPage: index == 0,
                  );
                  return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题块高度由 metrics 决定；矮到放不下就整块隐藏。
                  if (metrics.titleHeight > 0)
                    index == 0
                        ? Container(
                            height: metrics.titleHeight,
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
                        : SizedBox(
                            height: metrics.titleHeight,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                controller.currentChapterTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: textColor.withValues(alpha: 0.5),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                  Expanded(
                    child: menuVisible
                        ? Text(
                            textPages[index],
                            style: TextStyle(
                              fontSize: settings.fontSize,
                              height: settings.lineHeight,
                              letterSpacing: settings.letterSpacing + 0.6,
                              fontFamily: settings.fontFamily,
                              color: textColor,
                            ),
                          )
                        : SelectableText(
                            textPages[index],
                            contextMenuBuilder: (context, editableTextState) {
                              final selection =
                                  editableTextState.textEditingValue.selection;
                              String? selectedText;
                              if (selection.isValid && !selection.isCollapsed) {
                                selectedText =
                                    editableTextState.textEditingValue.text
                                        .substring(selection.start, selection.end);
                              }
                              return AdaptiveTextSelectionToolbar(
                                anchors: editableTextState.contextMenuAnchors,
                                children: [
                                  for (final item
                                      in editableTextState.contextMenuButtonItems)
                                    TextButton(
                                      onPressed: () {
                                        item.onPressed?.call();
                                        if (item.type !=
                                            ContextMenuButtonType.selectAll) {
                                          editableTextState.hideToolbar();
                                        }
                                      },
                                      child: Text(item.label ?? ''),
                                    ),
                                  if (selectedText != null &&
                                      selectedText.isNotEmpty)
                                    TextButton(
                                      onPressed: () {
                                        editableTextState.hideToolbar();
                                        final word = selectedText;
                                        if (word != null) {
                                          onLookupWord?.call(word);
                                        }
                                      },
                                      child: const Text('查词'),
                                    ),
                                ],
                              );
                            },
                            style: TextStyle(
                              fontSize: settings.fontSize,
                              height: settings.lineHeight,
                              letterSpacing: settings.letterSpacing + 0.6,
                              fontFamily: settings.fontFamily,
                              color: textColor,
                            ),
                          ),
                  ),
                ],
              );
                },
              ),
            ),
            // 底部页码/进度指示（绝对定位，不占用内容空间）
            Positioned(
              left: 20,
              right: 20,
              bottom: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '第 ${index + 1} / $totalPages 页',
                    style: TextStyle(
                      fontSize: 11,
                      color: textColor.withValues(alpha: 0.4),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    '${((index + 1) / totalPages * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 11,
                      color: textColor.withValues(alpha: 0.4),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'reader_controller.dart';

class ReaderContinuousView extends StatelessWidget {
  const ReaderContinuousView({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.topPadding,
    required this.textColor,
    required this.onLoadNextChapter,
    this.onLookupWord,
  });

  static const double _preloadThreshold = 2000;
  static const double _emptyPaddingTopExtra = 120;
  static const EdgeInsets _listPadding = EdgeInsets.fromLTRB(20, 0, 20, 100);
  static const EdgeInsets _endPadding = EdgeInsets.only(top: 60, bottom: 40);
  static const EdgeInsets _loadingPadding = EdgeInsets.only(top: 50, bottom: 50);
  static const double _firstChapterTopExtra = 16;
  static const double _chapterTopPadding = 80;
  static const double _chapterTitleFontSize = 28;
  static const double _chapterTitleHeight = 1.2;
  static const double _chapterSpacing = 30;
  static const double _progressIndicatorStroke = 2.5;
  static const double _loadingAlpha = 0.35;
  static const double _endTextAlpha = 0.4;
  static const double _endTextLetterSpacing = 2;
  static const Duration _preloadDebounce = Duration(milliseconds: 300);

  final ReaderController controller;
  final ScrollController scrollController;
  final double topPadding;
  final Color textColor;
  final Future<void> Function() onLoadNextChapter;

  /// 查词回调（从 contextMenuBuilder -> 选中文字）
  final void Function(String word)? onLookupWord;

  @override
  Widget build(BuildContext context) {
    Timer? debounce;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis != Axis.vertical) return false;

        if (notification.metrics.extentAfter < _preloadThreshold &&
            !controller.loadingNextScroll &&
            controller.canGoNext) {
          if (debounce?.isActive ?? false) return false;
          debounce = Timer(_preloadDebounce, () {
            unawaited(onLoadNextChapter());
          });
        }

        return false;
      },
      child: ListView.builder(
        controller: scrollController,
        physics: const BouncingScrollPhysics(),
        padding: _listPadding,
        itemCount: controller.scrollItems.length + 1,
        itemBuilder: (context, index) {
          if (controller.scrollItems.isEmpty) {
            return Padding(
              padding: EdgeInsets.only(top: topPadding + _emptyPaddingTopExtra),
              child: Center(
                child: CircularProgressIndicator(
                  color: textColor.withValues(alpha: _loadingAlpha),
                  strokeWidth: _progressIndicatorStroke,
                ),
              ),
            );
          }

          if (index == controller.scrollItems.length) {
            final isLastInWholeBook =
                controller.scrollItems.last.index >=
                controller.totalChapters - 1;

            if (isLastInWholeBook) {
              return Padding(
                padding: _endPadding,
                child: Center(
                  child: Text(
                    '—— 全书完 ——',
                    style: TextStyle(
                      color: textColor.withValues(alpha: _endTextAlpha),
                      letterSpacing: _endTextLetterSpacing,
                    ),
                  ),
                ),
              );
            }

            return Padding(
              padding: _loadingPadding,
              child: Center(
                child: CircularProgressIndicator(
                  color: textColor.withValues(alpha: _loadingAlpha),
                  strokeWidth: _progressIndicatorStroke,
                ),
              ),
            );
          }

          final item = controller.scrollItems[index];

          return Container(
            padding: EdgeInsets.only(
              top: index == 0 ? topPadding + _firstChapterTopExtra : _chapterTopPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: _chapterTitleFontSize,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    height: _chapterTitleHeight,
                  ),
                ),
                const SizedBox(height: _chapterSpacing),
                SelectableText(
                  item.content,
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
                        if (selectedText != null && selectedText.isNotEmpty)
                          TextButton(
                            onPressed: () {
                              editableTextState.hideToolbar();
                              final word = selectedText;
                              if (word != null) onLookupWord?.call(word);
                            },
                            child: const Text('查词'),
                          ),
                      ],
                    );
                  },
                  style: TextStyle(
                    fontSize: controller.settings.fontSize,
                    height: controller.settings.lineHeight,
                    letterSpacing: controller.settings.letterSpacing + 0.6,
                    fontFamily: controller.settings.fontFamily,
                    color: textColor,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

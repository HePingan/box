import 'dart:async';

import 'package:flutter/material.dart';

import 'reader_controller.dart';

class ReaderContinuousView extends StatefulWidget {
  const ReaderContinuousView({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.topPadding,
    required this.textColor,
    required this.onLoadNextChapter,
    this.onLookupWord,
    this.menuVisible = false,
  });

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
  static const Duration preloadDebounce = Duration(milliseconds: 300);

  final ReaderController controller;
  final ScrollController scrollController;
  final double topPadding;
  final Color textColor;
  final Future<void> Function() onLoadNextChapter;

  /// 查词回调（从 contextMenuBuilder -> 选中文字）
  final void Function(String word)? onLookupWord;

  /// 菜单是否可见，影响 SelectableText 是否启用选词功能
  final bool menuVisible;

  @override
  State<ReaderContinuousView> createState() => _ReaderContinuousViewState();
}

class _ReaderContinuousViewState extends State<ReaderContinuousView> {
  Timer? _preloadDebounce;

  @override
  void dispose() {
    _preloadDebounce?.cancel();
    super.dispose();
  }

  void _maybePreloadNext() {
    if (_preloadDebounce?.isActive ?? false) return;
    _preloadDebounce = Timer(ReaderContinuousView.preloadDebounce, () {
      if (mounted) {
        unawaited(widget.onLoadNextChapter());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
            if (notification.metrics.axis != Axis.vertical) return false;

            // 预加载阈值可从 settings 获取，默认 2000
            final threshold = widget.controller.settings.prefetchAheadPx;
            if (notification.metrics.extentAfter < threshold &&
                !widget.controller.loadingNextScroll &&
                widget.controller.canGoNext) {
              _maybePreloadNext();
            }

            return false;
          },
      child: ListView.builder(
        controller: widget.scrollController,
        physics: const BouncingScrollPhysics(),
        padding: ReaderContinuousView._listPadding,
        itemCount: widget.controller.scrollItems.length + 1,
        itemBuilder: (context, index) {
          if (widget.controller.scrollItems.isEmpty) {
            return Padding(
              padding: EdgeInsets.only(top: widget.topPadding + ReaderContinuousView._emptyPaddingTopExtra),
              child: Center(
                child: CircularProgressIndicator(
                  color: widget.textColor.withValues(alpha: ReaderContinuousView._loadingAlpha),
                  strokeWidth: ReaderContinuousView._progressIndicatorStroke,
                ),
              ),
            );
          }

          if (index == widget.controller.scrollItems.length) {
            final isLastInWholeBook =
                widget.controller.scrollItems.last.index >=
                widget.controller.totalChapters - 1;

            if (isLastInWholeBook) {
              return Padding(
                padding: ReaderContinuousView._endPadding,
                child: Center(
                  child: Text(
                    '—— 全书完 ——',
                    style: TextStyle(
                      color: widget.textColor.withValues(alpha: ReaderContinuousView._endTextAlpha),
                      letterSpacing: ReaderContinuousView._endTextLetterSpacing,
                    ),
                  ),
                ),
              );
            }

            return Padding(
              padding: ReaderContinuousView._loadingPadding,
              child: Center(
                child: CircularProgressIndicator(
                  color: widget.textColor.withValues(alpha: ReaderContinuousView._loadingAlpha),
                  strokeWidth: ReaderContinuousView._progressIndicatorStroke,
                ),
              ),
            );
          }

          final item = widget.controller.scrollItems[index];

          return Container(
            padding: EdgeInsets.only(
              top: index == 0 ? widget.topPadding + ReaderContinuousView._firstChapterTopExtra : ReaderContinuousView._chapterTopPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: ReaderContinuousView._chapterTitleFontSize,
                    fontWeight: FontWeight.bold,
                    color: widget.textColor,
                    height: ReaderContinuousView._chapterTitleHeight,
                  ),
                ),
                const SizedBox(height: ReaderContinuousView._chapterSpacing),
                widget.menuVisible
                    ? Text(
                        item.content,
                        style: TextStyle(
                          fontSize: widget.controller.settings.fontSize,
                          height: widget.controller.settings.lineHeight,
                          letterSpacing:
                              widget.controller.settings.letterSpacing + 0.6,
                          fontFamily: widget.controller.settings.fontFamily,
                          color: widget.textColor,
                        ),
                      )
                    : SelectableText(
                        item.content,
                        contextMenuBuilder: (context, editableTextState) {
                          final selection =
                              editableTextState.textEditingValue.selection;
                          String? selectedText;
                          if (selection.isValid &&
                              !selection.isCollapsed) {
                            selectedText =
                                editableTextState.textEditingValue.text
                                    .substring(selection.start,
                                        selection.end);
                          }
                          return AdaptiveTextSelectionToolbar(
                            anchors: editableTextState.contextMenuAnchors,
                            children: [
                              for (final menuitem
                                  in editableTextState
                                      .contextMenuButtonItems)
                                TextButton(
                                  onPressed: () {
                                    menuitem.onPressed?.call();
                                    if (menuitem.type !=
                                        ContextMenuButtonType.selectAll) {
                                      editableTextState.hideToolbar();
                                    }
                                  },
                                  child: Text(menuitem.label ?? ''),
                                ),
                              if (selectedText != null &&
                                  selectedText.isNotEmpty)
                                TextButton(
                                  onPressed: () {
                                    editableTextState.hideToolbar();
                                    final word = selectedText;
                                    if (word != null) {
                                      widget.onLookupWord?.call(word);
                                    }
                                  },
                                  child: const Text('查词'),
                                ),
                            ],
                          );
                        },
                        style: TextStyle(
                          fontSize: widget.controller.settings.fontSize,
                          height: widget.controller.settings.lineHeight,
                          letterSpacing:
                              widget.controller.settings.letterSpacing + 0.6,
                          fontFamily: widget.controller.settings.fontFamily,
                          color: widget.textColor,
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

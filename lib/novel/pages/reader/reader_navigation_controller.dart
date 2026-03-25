import 'dart:async';

import 'package:flutter/material.dart';

import 'reader_controller.dart';

class ReaderNavigationController extends ChangeNotifier {
  ReaderNavigationController({
    required this.readerController,
    required this.pageController,
    required this.scrollController,
    required this.getTextPages,
    required this.onResetPagedState,
    required this.scheduleScrollJump,
  }) : jumpTarget = ReaderJumpTarget.restoreDb;

  final ReaderController readerController;
  final PageController pageController;
  final ScrollController scrollController;

  /// 由页面提供当前分页结果
  final List<String> Function() getTextPages;

  /// 切章前，页面需要清理的状态
  final void Function(ReaderJumpTarget target) onResetPagedState;

  /// 切到滚动模式章节后，需要把滚动位置跳回目标点
  final VoidCallback scheduleScrollJump;

  ReaderJumpTarget jumpTarget;

  bool get isScrollMode => readerController.isScrollMode;
  bool get showMenu => readerController.showMenu;

  void setJumpTarget(ReaderJumpTarget target) {
    jumpTarget = target;
    notifyListeners();
  }

  int currentPageIndex() {
    final pages = getTextPages();
    if (pages.isEmpty || !pageController.hasClients) return 0;

    final idx = (pageController.page ?? 1.0).round() - 1;
    return idx.clamp(0, pages.length - 1);
  }

  Future<void> switchChapter(
    int index, {
    required ReaderJumpTarget target,
  }) async {
    if (index < 0 || index >= readerController.totalChapters) return;

    jumpTarget = target;
    onResetPagedState(target);

    await readerController.switchChapter(index, target: target);

    if (readerController.isScrollMode) {
      scheduleScrollJump();
    }

    notifyListeners();
  }

  Future<void> handlePageChanged(int viewIndex) async {
    if (readerController.isScrollMode) return;

    final pages = getTextPages();
    if (pages.isEmpty) return;

    final tail = pages.length + 1;

    if (viewIndex == 0) {
      if (readerController.canGoPrev) {
        await switchChapter(
          readerController.chapterIndex - 1,
          target: ReaderJumpTarget.end,
        );
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (pageController.hasClients) {
            pageController.jumpToPage(1);
          }
        });
      }
      return;
    }

    if (viewIndex == tail) {
      if (readerController.canGoNext) {
        await switchChapter(
          readerController.chapterIndex + 1,
          target: ReaderJumpTarget.start,
        );
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (pageController.hasClients) {
            pageController.jumpToPage(pages.length);
          }
        });
      }
      return;
    }

    // 中间页：交给页面层去保存进度
    notifyListeners();
  }

  Future<void> handleScreenTap(
    TapUpDetails details,
    BuildContext context,
  ) async {
    if (readerController.showMenu) {
      readerController.setMenuVisible(false);
      return;
    }

    final size = MediaQuery.of(context).size;
    final x = details.globalPosition.dx;
    final y = details.globalPosition.dy;

    // 中间区域：打开菜单
    if (x > size.width * 0.33 &&
        x < size.width * 0.66 &&
        y > size.height * 0.33 &&
        y < size.height * 0.66) {
      readerController.setMenuVisible(true);
      return;
    }

    // 连续滚动模式：点击上半屏 / 下半屏滚动
    if (readerController.isScrollMode) {
      if (!scrollController.hasClients) return;

      final step = size.height * 0.82;
      final current = scrollController.offset;

      if (y < size.height * 0.33) {
        scrollController.animateTo(
          (current - step).clamp(
            0.0,
            scrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } else if (y > size.height * 0.66) {
        scrollController.animateTo(
          (current + step).clamp(
            0.0,
            scrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    // 分页模式
    final pages = getTextPages();
    if (pages.isEmpty || !pageController.hasClients) return;

    if (x < size.width * 0.33) {
      // 左侧：上一页 / 上一章
      if (currentPageIndex() <= 0) {
        if (readerController.canGoPrev) {
          unawaited(
            switchChapter(
              readerController.chapterIndex - 1,
              target: ReaderJumpTarget.end,
            ),
          );
        }
      } else {
        pageController.previousPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    } else {
      // 右侧：下一页 / 下一章
      if (currentPageIndex() >= pages.length - 1) {
        if (readerController.canGoNext) {
          unawaited(
            switchChapter(
              readerController.chapterIndex + 1,
              target: ReaderJumpTarget.start,
            ),
          );
        }
      } else {
        pageController.nextPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    }
  }
}
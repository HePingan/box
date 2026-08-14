import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  // ── 菜单状态（提升到此控制器，避免 ReaderController 高频 notify 重建菜单）──
  bool _menuVisible = false;
  bool get menuVisible => _menuVisible;

  /// 点击屏幕中央区域切换菜单
  void toggleMenu() {
    _menuVisible = !_menuVisible;
    notifyListeners();
  }

  /// 关闭菜单（由目录/书签/设置等弹窗关闭时调用）
  void dismissMenu() {
    if (!_menuVisible) return;
    _menuVisible = false;
    notifyListeners();
  }

  /// 当前是否启用震动反馈
  bool get enableHaptic => readerController.settings.enableHaptic;

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

    if (enableHaptic) HapticFeedback.lightImpact();
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
    // 菜单显示时点击任意位置关闭菜单
    if (menuVisible) {
      dismissMenu();
      return;
    }

    final size = MediaQuery.of(context).size;
    final x = details.globalPosition.dx;
    final y = details.globalPosition.dy;

    // 中间区域：切换菜单 (30%-70%, 更宽的触发区)
    if (x > size.width * 0.30 &&
        x < size.width * 0.70 &&
        y > size.height * 0.25 &&
        y < size.height * 0.75) {
      if (enableHaptic) HapticFeedback.lightImpact();
      toggleMenu();
      return;
    }

    // 连续滚动模式：点击上半屏 / 下半屏滚动
    if (readerController.isScrollMode) {
      if (!scrollController.hasClients) return;

      if (y < size.height * 0.33) {
        goPrevious(viewportHeight: size.height);
      } else if (y > size.height * 0.66) {
        goNext(viewportHeight: size.height);
      }
      return;
    }

    // 分页模式
    final pages = getTextPages();
    if (pages.isEmpty || !pageController.hasClients) return;

    if (x < size.width * 0.33) {
      goPrevious(viewportHeight: size.height);
    } else {
      goNext(viewportHeight: size.height);
    }
  }

  /// 上一页 / 上一章（分页模式），或向上滚动一屏（滚动模式）。
  ///
  /// 抽成公开方法供点击与音量键共用，两条输入路径的翻页语义
  /// （边界切章、震动反馈、动画曲线）必须完全一致。
  void goPrevious({required double viewportHeight}) {
    if (readerController.isScrollMode) {
      if (!scrollController.hasClients) return;
      final step = viewportHeight * 0.82;
      if (enableHaptic) HapticFeedback.lightImpact();
      scrollController.animateTo(
        (scrollController.offset - step).clamp(
          0.0,
          scrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    final pages = getTextPages();
    if (pages.isEmpty || !pageController.hasClients) return;

    if (currentPageIndex() <= 0) {
      // 已在本章首页：跳上一章并定位到末页
      if (readerController.canGoPrev) {
        unawaited(
          switchChapter(
            readerController.chapterIndex - 1,
            target: ReaderJumpTarget.end,
          ),
        );
      }
      return;
    }

    if (enableHaptic) HapticFeedback.lightImpact();
    pageController.previousPage(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  /// 下一页 / 下一章（分页模式），或向下滚动一屏（滚动模式）。
  void goNext({required double viewportHeight}) {
    if (readerController.isScrollMode) {
      if (!scrollController.hasClients) return;
      final step = viewportHeight * 0.82;
      if (enableHaptic) HapticFeedback.lightImpact();
      scrollController.animateTo(
        (scrollController.offset + step).clamp(
          0.0,
          scrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    final pages = getTextPages();
    if (pages.isEmpty || !pageController.hasClients) return;

    if (currentPageIndex() >= pages.length - 1) {
      // 已在本章末页：跳下一章并定位到首页
      if (readerController.canGoNext) {
        unawaited(
          switchChapter(
            readerController.chapterIndex + 1,
            target: ReaderJumpTarget.start,
          ),
        );
      }
      return;
    }

    if (enableHaptic) HapticFeedback.lightImpact();
    pageController.nextPage(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }
}

import 'package:flutter/material.dart';

/// 阅读器的纯展示层：加载骨架、错误态、顶部进度条、切章遮罩、分页角标。
///
/// 这些原本是 `_ReaderPageState` 上的 `_buildXxx` 方法。它们只读 State 字段、
/// 不写任何字段、不碰分页时序，属于可以安全搬走的部分——搬出来后
/// `reader_page.dart` 少约 200 行，且每个都能用 `pumpWidget` 独立测。
///
/// 分页时序相关的 `_buildPagedReaderView` 故意留在原地：它会写
/// `_lastFitWidth` / `_lastNormalHeight` 并触发 `_schedulePageRecalc`，
/// 搬动等于把三个耦合字段暴露出去。

/// 加载骨架屏：标题占位 + 5 行文字占位 + spinner。
///
/// 用骨架而非纯 spinner，是为了让切章时的布局不跳动。
class ReaderLoadingSkeleton extends StatelessWidget {
  const ReaderLoadingSkeleton({super.key, required this.textColor});

  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 章节标题占位
            Container(
              width: 180,
              height: 18,
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 28),
            // 文字行占位 ×5：宽度与深浅都做了轻微错落，避免看起来像表格
            for (int i = 0; i < 5; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Container(
                  height: 14,
                  width: 120.0 + (i * 40) % 160,
                  decoration: BoxDecoration(
                    color: textColor.withValues(
                      alpha: 0.08 + (i % 3) * 0.02,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: textColor.withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 错误态：图标 + 文案 + 重试按钮。
class ReaderErrorState extends StatelessWidget {
  const ReaderErrorState({
    super.key,
    required this.textColor,
    required this.message,
    required this.onRetry,
  });

  final Color textColor;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 52,
              color: textColor.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                color: textColor.withValues(alpha: 0.65),
                fontSize: 15,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部阅读进度条：2px 薄线，宽度表示当前章在全书中的位置。
///
/// 单章书（含未加载出目录时）显示进度条没有意义，直接收成零高度。
class ReaderTopProgressBar extends StatelessWidget {
  const ReaderTopProgressBar({
    super.key,
    required this.textColor,
    required this.chapterIndex,
    required this.totalChapters,
  });

  final Color textColor;
  final int chapterIndex;
  final int totalChapters;

  @override
  Widget build(BuildContext context) {
    if (totalChapters <= 1) return const SizedBox.shrink();

    final progress = (chapterIndex + 1) / totalChapters;

    return FractionallySizedBox(
      widthFactor: progress.clamp(0.0, 1.0),
      child: Container(
        height: 2,
        color: textColor.withValues(alpha: 0.30),
      ),
    );
  }
}

/// 切章转场遮罩：淡入到 55% 不透明度，显示目标章标题 + 可取消提示。
///
/// 不做全遮挡（上限 0.55）是刻意的：让用户仍能看到底下的正文，
/// 知道自己没有被弹到别的页面。
class ReaderChapterTransitionOverlay extends StatelessWidget {
  const ReaderChapterTransitionOverlay({
    super.key,
    required this.bgColor,
    required this.textColor,
    required this.title,
    required this.onCancel,
  });

  final Color bgColor;
  final Color textColor;
  final String title;

  /// 点击遮罩取消切章。是否真的可取消由调用方判断，这里只负责转发。
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return GestureDetector(
          onTap: onCancel,
          child: Opacity(
            opacity: value.clamp(0.0, 0.55),
            child: Container(
              color: bgColor,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor.withValues(alpha: 0.7 * value),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: textColor.withValues(alpha: 0.35 * value),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击取消',
                    style: TextStyle(
                      fontSize: 11,
                      color: textColor.withValues(alpha: 0.4 * value),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 后台增量分页进行中的角标。
///
/// 首屏只排前几页就先渲染，剩余页在后台继续排——这个角标是那段时间里
/// 唯一的可见反馈，去掉会让长章看起来像卡住了。
class ReaderPaginatingBadge extends StatelessWidget {
  const ReaderPaginatingBadge({
    super.key,
    required this.bgColor,
    required this.textColor,
  });

  final Color bgColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: textColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: textColor.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '排版中…',
            style: TextStyle(
              fontSize: 11,
              color: textColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

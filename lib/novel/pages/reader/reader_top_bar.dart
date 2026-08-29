import 'package:flutter/material.dart';

/// 阅读器顶栏。
///
/// 布局要点（都有 test/novel/reader/reader_top_bar_test.dart 锁着）：
///
/// 1. **横向铺满 + 不透明底色**。早先版本是「圆角悬浮卡片」：
///    margin 左右各留 10、底色 alpha 0.92。结果卡片外那圈直接露出正文，
///    半透明底色又压不住底下的深色文字，视觉上就是章节标题从顶栏背后
///    透出来的重影。顶栏本来就贴着屏幕顶边，做成悬浮卡片没有收益，
///    只会制造漏光缝隙 —— 所以改成整条铺满、底色完全不透明。
///
/// 2. **高度含安全区**。`padding.top` 计入高度并作为内边距下推内容，
///    否则刘海屏上图标会跟状态栏挤在一起。
///
/// 3. **收数据不收 controller**。早先直接吃 ReaderController，导致想测
///    布局就得造一个完整控制器（要 detail、章节列表、书签服务）。
///    现在只收 4 个值，纯展示、可单测。
class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.bookTitle,
    required this.chapterTitle,
    required this.hasBookmark,
    required this.bgColor,
    required this.textColor,
    required this.onBack,
    this.onBookmark,
    this.onDictionary,
  });

  final String bookTitle;

  /// 当前章节名。空字符串则整行省略，不留空位撑高顶栏。
  final String chapterTitle;

  final bool hasBookmark;
  final Color bgColor;
  final Color textColor;
  final VoidCallback onBack;
  final VoidCallback? onBookmark;
  final VoidCallback? onDictionary;

  /// 右侧图标与屏幕右边缘的间距。
  ///
  /// IconButton 默认 48 的点击区自带留白，视觉上右边距会显得比图标之间
  /// 的缝隙大一截（截图里「右侧重心偏散」就是这么来的）。这里收紧到 4，
  /// 让两者视觉接近；测试断言二者差值 < 12。
  static const double _edgeInset = 4;

  /// 顶栏内容高度（不含状态栏安全区）。
  ///
  /// 对外暴露是因为 reader_page 要按它给进度条定位 —— 两边各写一个 52
  /// 迟早会漂移，进度条就会压在顶栏上或悬空。
  static const double contentHeight = 52;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final hasChapter = chapterTitle.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.only(top: topInset),
      decoration: BoxDecoration(
        // 必须完全不透明：任何 alpha < 1 都会让底下的正文透出来。
        color: bgColor,
        border: Border(
          bottom: BorderSide(color: textColor.withValues(alpha: 0.08)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SizedBox(
        height: contentHeight,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: textColor,
                size: 20,
              ),
              tooltip: '返回',
              onPressed: onBack,
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bookTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                      height: 1.2,
                    ),
                  ),
                  if (hasChapter)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        chapterTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: textColor.withValues(alpha: 0.55),
                          height: 1.2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.menu_book_rounded, color: textColor, size: 20),
              tooltip: '词典',
              onPressed: onDictionary,
            ),
            IconButton(
              icon: Icon(
                hasBookmark
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                color: textColor,
                size: 20,
              ),
              tooltip: '书签',
              onPressed: onBookmark,
            ),
            const SizedBox(width: _edgeInset),
          ],
        ),
      ),
    );
  }
}

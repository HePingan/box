/// 阅读器分页视图的标题块 / 正文高度分配。
///
/// 抽出来是因为小窗（自由窗口、小窗模式）下可用高度可能比标题块本身还矮：
/// 红米 K80 小窗实测逻辑尺寸 101.7 x 162.7 dp，扣掉 padding 后第 0 页
/// 只剩 38.7dp，而第 0 页的大标题固定占 46dp —— Column 里 `Expanded`
/// 正文拿到 `38.7 - 46 < 0`，被压成零高，一个字都画不出。
///
/// 规则很简单：**标题给正文让位**。空间够就维持原有观感（首页 46dp
/// 大标题、其余页 24dp 小标题）；不够就按比例收缩，实在不够就隐藏标题。
class ReaderLayoutMetrics {
  const ReaderLayoutMetrics({
    required this.titleHeight,
    required this.textHeight,
  });

  /// 标题块高度。0 表示空间不足、标题完全隐藏。
  final double titleHeight;

  /// 留给正文的高度，恒 > 0（除非可用高度本身 <= 0）。
  final double textHeight;

  /// 首页大标题的理想高度（fontSize 26 + 8 底部间距）。
  static const double firstPageTitleHeight = 46.0;

  /// 非首页小标题的理想高度（fontSize 10）。
  static const double normalPageTitleHeight = 24.0;

  /// 正文至少要保住的高度，低于这个值就没有阅读意义，
  /// 但仍然要 > 0 以免 Flutter 抛布局异常。
  static const double minTextHeight = 16.0;

  /// 正文左右各 20dp 的水平内边距合计（reader_paged_view.dart:117）。
  static const double horizontalPadding = 40.0;

  /// 分页宽度上限：超宽屏上一行太长会难读。
  static const double maxFitWidth = 660.0;

  /// 由窗口约束宽算出交给分页器的排版宽度。
  ///
  /// 这里**不能有 200 之类的下限**：小窗宽度可以只有 101.7dp
  /// （红米 K80 实测），减去 padding 后是 61.7dp。过去写成
  /// `clamp(200.0, 660.0)` 会把 61.7 抬到 200，分页器按一行 10 个字切页，
  /// 而正文实际只放得下 3 个字 —— 每行溢出被裁，正文区看起来一片空白。
  ///
  /// 下限只用来兜「尺寸还没就绪」（<=0），不能用来假装窗口更宽。
  static double resolveFitWidth(double maxWidth) {
    final raw = maxWidth - horizontalPadding;
    if (raw <= 0) return 0;
    return raw > maxFitWidth ? maxFitWidth : raw;
  }

  static ReaderLayoutMetrics resolve({
    required double availableHeight,
    required bool isFirstPage,
  }) {
    // 尺寸还没就绪：全部归零，交给上层的 spinner 守卫。
    if (availableHeight <= 0) {
      return const ReaderLayoutMetrics(titleHeight: 0, textHeight: 0);
    }

    final ideal = isFirstPage ? firstPageTitleHeight : normalPageTitleHeight;

    // 空间充足：保持既有观感，一个像素都不改。
    if (availableHeight - ideal >= minTextHeight) {
      return ReaderLayoutMetrics(
        titleHeight: ideal,
        textHeight: availableHeight - ideal,
      );
    }

    // 空间不足：正文优先，标题拿剩下的。
    // 留给标题的高度可能为 0（彻底隐藏），这是有意的 —— 小窗里
    // 用户要的是正文，不是一个把正文挤没的标题。
    final titleHeight = (availableHeight - minTextHeight).clamp(0.0, ideal);
    return ReaderLayoutMetrics(
      titleHeight: titleHeight,
      textHeight: availableHeight - titleHeight,
    );
  }
}

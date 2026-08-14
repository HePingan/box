/// 分页进度定位：在「原文字符偏移」与「页索引」之间换算。
///
/// 为什么需要这层：旧逻辑只存页索引，而页索引依赖字号、行高、字间距、
/// 屏幕宽高。用户改一次字号或横竖屏切换，同一个索引就指向完全不同的正文，
/// 「继续阅读」会跳到错误位置。字符偏移是排版无关的锚点。
library;

/// 计算每一页在原文中的起始字符偏移。
///
/// 分页器会跳过页首连续换行，所以「页长度累加」并不等于原文偏移 ——
/// 必须回原文里定位。用 [String.indexOf] 顺序推进游标，保证得到的是
/// 真实偏移而非累加值。
///
/// 返回长度与 [pages] 一致；定位失败的页回退为前一页的偏移（单调不减）。
List<int> computePageStartOffsets(List<String> pages, String content) {
  final offsets = <int>[];
  var cursor = 0;

  for (final page in pages) {
    if (page.isEmpty) {
      offsets.add(cursor);
      continue;
    }

    final found = content.indexOf(page, cursor);
    if (found < 0) {
      // 内容与分页结果不匹配（理论上不该发生）。
      // 退化为上一页偏移，保持单调不减，避免二分查找失效。
      offsets.add(offsets.isEmpty ? 0 : offsets.last);
      continue;
    }

    offsets.add(found);
    cursor = found + page.length;
  }

  return offsets;
}

/// 找出包含 [charOffset] 的页索引。
///
/// [pageStartOffsets] 必须单调不减（[computePageStartOffsets] 保证这点）。
/// 偏移落在两页之间时取靠前的那一页 —— 宁可让用户重读半句，
/// 也不要跳过没读过的内容。
int locatePageForCharOffset(List<int> pageStartOffsets, int charOffset) {
  if (pageStartOffsets.isEmpty) return 0;
  if (charOffset <= pageStartOffsets.first) return 0;

  // 二分找最后一个 start <= charOffset
  var low = 0;
  var high = pageStartOffsets.length - 1;
  var best = 0;

  while (low <= high) {
    final mid = low + ((high - low) ~/ 2);
    if (pageStartOffsets[mid] <= charOffset) {
      best = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  return best;
}

/// 计算某一页的起始字符偏移，用于保存进度。
///
/// [pageIndex] 越界时返回 null，调用方应降级为不写 charOffset。
int? charOffsetForPage(List<String> pages, String content, int pageIndex) {
  if (pageIndex < 0 || pageIndex >= pages.length) return null;
  final offsets = computePageStartOffsets(pages, content);
  return offsets[pageIndex];
}

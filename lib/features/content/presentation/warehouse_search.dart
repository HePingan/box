import '../domain/warehouse_models.dart';

/// 收藏项搜索筛选。
///
/// 从 warehouse_tab 的私有 `_filtered` 提取出来，便于单测覆盖。
/// 对 query 做 trim：用户从别处粘贴书名常带首尾空格，不 trim 会零命中。
List<WarehouseItem> warehouseFilter(List<WarehouseItem> items, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items;
  return items.where((item) {
    return item.title.toLowerCase().contains(q) ||
        item.subtitle.toLowerCase().contains(q) ||
        item.meta.toLowerCase().contains(q);
  }).toList();
}

/// 是否处于「搜索无结果」态。
///
/// 必须与「收藏库本来就空」区分开：
/// - 库里有东西 + 有搜索词 + 零命中 → 搜索无结果，应提示换个词/清除搜索
/// - 库本来就空 → 走各分区原本的空态引导（去书架同步、手动收藏等）
///
/// 原实现里搜索零命中会让四个分区全部 `_shouldShowSection == false`，
/// 页面上只剩顶部卡片和搜索框，用户会误以为收藏被清空了。
bool isWarehouseNoSearchResult({
  required String query,
  required int totalItemsInLibrary,
  required int totalMatched,
}) {
  return query.trim().isNotEmpty &&
      totalItemsInLibrary > 0 &&
      totalMatched == 0;
}

/// 把选中集收敛到当前仍可见的项。
///
/// 编辑模式下先勾选若干项、再输入搜索词时，不匹配的条目会从界面消失，
/// 但它们的 key 仍留在选中集里。此时点批量删除会连带删掉屏幕上看不见的项，
/// 且确认弹窗的计数与用户认知不符。
Set<String> retainVisibleSelection({
  required Set<String> selected,
  required List<WarehouseItem> visibleItems,
}) {
  final visibleKeys = visibleItems.map((e) => e.uniqueKey).toSet();
  return selected.where(visibleKeys.contains).toSet();
}

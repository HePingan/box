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

/// 某个收藏分区是否应该显示。
///
/// 契约：可见性**只**由「该分区自己的命中结果 + 是否在搜索」决定，
/// 不允许按分类硬编码。原实现里 videos/comics/music 在有搜索词时直接
/// `return false`，配合 `_itemsForCategory` 对非 books 恒返回 const []，
/// 造成用户报障的「影视收藏没显示出来」——数据在 Hive 里真实存在，
/// 但分区永远不出现。
///
/// - 有搜索词：该分区有命中才显示（否则空分区刷屏）
/// - 无搜索词：恒显示，空分区要展示自己的空态引导
bool shouldShowWarehouseSection({
  required String searchQuery,
  required List<WarehouseItem> matchedInSection,
}) {
  if (searchQuery.trim().isEmpty) return true;
  return matchedInSection.isNotEmpty;
}

/// 收藏总数 = 各分区之和。
///
/// 原实现只数 books，接上影视/漫画后不改会让顶部「共 N 项」撒谎。
int warehouseTotalItems(List<List<WarehouseItem>> sections) {
  var total = 0;
  for (final section in sections) {
    total += section.length;
  }
  return total;
}

/// 非空分区数。顶部统计用，空分区不计。
int warehouseNonEmptySectionCount(List<List<WarehouseItem>> sections) {
  return sections.where((e) => e.isNotEmpty).length;
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

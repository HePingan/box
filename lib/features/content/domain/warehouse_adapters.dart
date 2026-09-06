import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/content/domain/warehouse_models.dart';
import 'package:box/video/models/video_source.dart';
import 'package:box/video/services/favorites_repository.dart';

/// 把各模块的真实收藏数据转成收藏库统一的 [WarehouseItem]。
///
/// 为什么单独成 domain 文件而不是塞进 `warehouse_tab`：
/// 影视收藏（Hive `video_favorites_box`）和漫画收藏（CacheStore `comic_library`）
/// 各有自己的存储与模型，页面里如果就地手写转换，逻辑会被 widget 状态裹住，
/// 只能靠搭整页 + mock 一大片才能测。这里保持纯函数，测试可以直接调。
///
/// 边界：这两条都是**实时通道**，和已下线的手填收藏（`sourceLabel == '手动收藏'`，
/// 落在 `warehouse_center` namespace）没有关系，不会被 [WarehouseCleanup] 清掉。

/// 影视收藏在收藏库里的来源标记。
const String videoFavoriteSourceLabel = '影视收藏';

/// 漫画收藏在收藏库里的来源标记。
const String comicFavoriteSourceLabel = '漫画收藏';

/// 小说书架在收藏库里的来源标记。
///
/// 原先这个字符串在 `_loadBooks`、`_syncLabel` 两处各写一遍字面量，
/// 判定逻辑要认这个值，散着写迟早对不上。
const String bookshelfSourceLabel = '书架';

/// 单条影视收藏 → [WarehouseItem]。
///
/// `detailUrl` 故意留空：影视收藏是「源 + vodId」定位的，没有稳定详情页 URL，
/// 塞一个假的进去会让 [WarehouseItem.uniqueKey] 认错条目。留空后 uniqueKey
/// 退化到 `videos_<sourceId>::<vodId>`，与 Hive 里的存储键一一对应。
WarehouseItem warehouseItemFromFavorite(FavoriteItem item) {
  final subtitleParts = <String>[
    item.typeName?.trim() ?? '',
    item.sourceName.trim(),
  ].where((e) => e.isNotEmpty).toList();

  return WarehouseItem(
    id: '${item.sourceId}::${item.vodId}',
    title: item.vodName,
    subtitle: subtitleParts.join(' · '),
    coverUrl: item.vodPic?.trim() ?? '',
    detailUrl: '',
    meta: item.vodRemarks?.trim() ?? '',
    category: WarehouseCategory.videos,
    sourceLabel: videoFavoriteSourceLabel,
    createdAt: item.savedAt,
    raw: item,
  );
}

/// 单条漫画收藏 → [WarehouseItem]。
///
/// 漫画封面是**本地文件路径**（解压出来的 cover.jpg），不是 http URL，
/// 所以这里原样带出，由 UI 侧用 [warehouseCoverIsLocalFile] 判断该走
/// `Image.file` 还是 `Image.network`。
WarehouseItem warehouseItemFromComicBook(ComicBook book) {
  final pageCount = book.pageCount ?? book.pages.length;
  final subtitleParts = <String>[
    switch (book.sourceType) {
      ComicSourceType.file => '本地文件',
      ComicSourceType.folder => '本地文件夹',
    },
    if (pageCount > 0) '$pageCount 页',
  ];

  return WarehouseItem(
    id: book.id,
    title: book.title,
    subtitle: subtitleParts.join(' · '),
    coverUrl: book.coverPath?.trim() ?? '',
    detailUrl: '',
    meta: '',
    category: WarehouseCategory.comics,
    sourceLabel: comicFavoriteSourceLabel,
    createdAt: book.createdAt,
    raw: book,
  );
}

/// 从已加载的片源列表里反查某条收藏对应的 [VideoSource]。
///
/// 收藏记录只存了 `sourceId` / `sourceUrl` 字符串，跳详情页却需要完整的
/// VideoSource 实例。这段逻辑原先只存在于 `favorites_page` 的私有方法里，
/// 收藏库要跳转就得复制一份 —— 两处各自演化必然漂移，所以提到 domain 层共用。
///
/// 匹配顺序：先按 id 精确匹配，再回退按 URL（收藏时 sourceId 可能取的是 url）。
VideoSource? findVideoSourceForFavorite(
  List<VideoSource> sources,
  FavoriteItem item,
) {
  for (final source in sources) {
    if (source.id == item.sourceId) return source;
  }
  for (final source in sources) {
    if (source.url == item.sourceId || source.url == item.sourceUrl) {
      return source;
    }
  }
  return null;
}

List<WarehouseItem> warehouseItemsFromFavorites(Iterable<FavoriteItem> items) =>
    items.map(warehouseItemFromFavorite).toList();

List<WarehouseItem> warehouseItemsFromComicBooks(Iterable<ComicBook> books) =>
    books.map(warehouseItemFromComicBook).toList();

/// 封面是否是本地文件路径（而非网络 URL）。
///
/// 漫画封面走本地路径，影视/小说走 http(s)。UI 若一律用 `Image.network`，
/// 漫画封面会全部落到 errorBuilder 兜底图 —— 看起来「有收藏但没封面」。
bool warehouseCoverIsLocalFile(String coverUrl) {
  final value = coverUrl.trim();
  if (value.isEmpty) return false;
  final lower = value.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) return false;
  if (lower.startsWith('data:')) return false;
  return value.startsWith('/') || value.startsWith('file:');
}

/// 本地封面路径去掉 `file://` 前缀，交给 `Image.file` 用。
String warehouseLocalCoverPath(String coverUrl) {
  final value = coverUrl.trim();
  if (value.toLowerCase().startsWith('file://')) {
    return Uri.parse(value).toFilePath();
  }
  return value;
}

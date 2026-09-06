// 红灯回归：内容页收藏库「影视收藏」永远空白。
//
// 真实现象（用户报障）：内容页收藏库里影视收藏没显示出来。
// 代码事实：warehouse_tab 的 `_itemsForCategory` 对 books 之外的分类恒返回
// const []，`_shouldShowSection` 在搜索时对 videos/comics/music 恒返回 false，
// 而页面副标题却写着「我的书架 / 影视收藏 / 漫画收藏 / 音乐收藏」——
// 数据其实存在（Hive video_favorites_box / CacheStore comic_library），
// 只是从没接进渲染。
//
// 这里只测纯适配逻辑：转换正确 + 唯一键与存储键对齐 + 封面类型判定。
// 整页 widget 依赖 Hive/CacheStore/书架三条真实通道，搭起来要 mock 一大片，
// 缺陷本身都落在可提取的纯函数里。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/content/domain/warehouse_adapters.dart';
import 'package:box/features/content/domain/warehouse_models.dart';
import 'package:box/video/services/favorites_repository.dart';

FavoriteItem _fav({
  String sourceId = 'src_a',
  String sourceName = '示例源',
  int vodId = 42,
  String vodName = '流浪地球',
  String? vodPic = 'https://example.com/a.jpg',
  String? vodRemarks = '已完结',
  String? typeName = '科幻',
  int savedAt = 1000,
}) {
  return FavoriteItem(
    sourceId: sourceId,
    sourceName: sourceName,
    sourceUrl: 'https://example.com/api',
    vodId: vodId,
    vodName: vodName,
    vodPic: vodPic,
    vodRemarks: vodRemarks,
    typeName: typeName,
    savedAt: savedAt,
  );
}

ComicBook _comic({
  String id = 'comic_1',
  String title = '海贼王',
  String? coverPath = '/data/user/0/app/cache/comic/cover.jpg',
  ComicSourceType sourceType = ComicSourceType.file,
  int pageCount = 20,
  int createdAt = 2000,
}) {
  return ComicBook(
    id: id,
    title: title,
    coverPath: coverPath,
    sourceType: sourceType,
    pageCount: pageCount,
    createdAt: createdAt,
  );
}

void main() {
  group('影视收藏必须能转成收藏库条目（否则分区永远空白）', () {
    test('标题/封面/来源/时间都取自真实收藏记录，不凭空造值', () {
      final item = warehouseItemFromFavorite(_fav());

      expect(item.category, WarehouseCategory.videos);
      expect(item.title, '流浪地球');
      expect(item.coverUrl, 'https://example.com/a.jpg');
      expect(item.createdAt, 1000, reason: 'createdAt 必须是真实 savedAt，不能用 now()');
      expect(item.sourceLabel, videoFavoriteSourceLabel);
      expect(item.meta, '已完结');
      expect(item.subtitle, contains('科幻'));
      expect(item.subtitle, contains('示例源'));
    });

    test('uniqueKey 必须与 Hive 存储键 sourceId::vodId 对齐（删除要靠它定位）', () {
      final item = warehouseItemFromFavorite(_fav(sourceId: 'src_b', vodId: 7));
      expect(item.id, 'src_b::7');
      // detailUrl 留空 → uniqueKey 退化到 category_id
      expect(item.uniqueKey, 'videos_src_b::7');
    });

    test('同源同 id 的两条收藏不会互相顶掉；不同源的同 vodId 互不冲突', () {
      final a = warehouseItemFromFavorite(_fav(sourceId: 'src_a', vodId: 1));
      final b = warehouseItemFromFavorite(_fav(sourceId: 'src_b', vodId: 1));
      expect(a.uniqueKey, isNot(b.uniqueKey));
    });

    test('缺失封面/备注不应崩，也不应写成字符串 "null"', () {
      final item = warehouseItemFromFavorite(
        _fav(vodPic: null, vodRemarks: null, typeName: null),
      );
      expect(item.coverUrl, isEmpty);
      expect(item.meta, isEmpty);
      expect(item.subtitle, isNot(contains('null')));
    });

    test('批量转换保持顺序（仓库层已按 savedAt 倒序）', () {
      final items = warehouseItemsFromFavorites([
        _fav(vodId: 1, savedAt: 300),
        _fav(vodId: 2, savedAt: 200),
      ]);
      expect(items.map((e) => e.createdAt).toList(), [300, 200]);
    });
  });

  group('漫画收藏必须能转成收藏库条目', () {
    test('页数与来源类型进副标题，createdAt 用真实值', () {
      final item = warehouseItemFromComicBook(_comic());
      expect(item.category, WarehouseCategory.comics);
      expect(item.title, '海贼王');
      expect(item.createdAt, 2000);
      expect(item.sourceLabel, comicFavoriteSourceLabel);
      expect(item.subtitle, contains('本地文件'));
      expect(item.subtitle, contains('20 页'));
    });

    test('文件夹来源标注为「本地文件夹」', () {
      final item = warehouseItemFromComicBook(
        _comic(sourceType: ComicSourceType.folder),
      );
      expect(item.subtitle, contains('本地文件夹'));
    });

    test('页数为 0 时不显示「0 页」这种废信息', () {
      final item = warehouseItemFromComicBook(_comic(pageCount: 0));
      expect(item.subtitle, isNot(contains('0 页')));
    });

    test('uniqueKey 用漫画 id，删除时能定位到 ComicLibraryStore 的记录', () {
      final item = warehouseItemFromComicBook(_comic(id: 'c_99'));
      expect(item.uniqueKey, 'comics_c_99');
    });
  });

  group('封面类型判定（漫画封面是本地路径，一律 Image.network 会全变兜底图）', () {
    test('本地绝对路径判为本地文件', () {
      expect(warehouseCoverIsLocalFile('/data/app/cover.jpg'), isTrue);
    });

    test('file:// 判为本地文件，并能转成可用路径', () {
      expect(warehouseCoverIsLocalFile('file:///tmp/a.jpg'), isTrue);
      expect(warehouseLocalCoverPath('file:///tmp/a.jpg'), '/tmp/a.jpg');
    });

    test('http/https 不是本地文件', () {
      expect(warehouseCoverIsLocalFile('https://example.com/a.jpg'), isFalse);
      expect(warehouseCoverIsLocalFile('http://example.com/a.jpg'), isFalse);
    });

    test('空封面不判为本地文件（应走兜底图，不要拿空路径去 Image.file）', () {
      expect(warehouseCoverIsLocalFile(''), isFalse);
      expect(warehouseCoverIsLocalFile('   '), isFalse);
    });
  });
}

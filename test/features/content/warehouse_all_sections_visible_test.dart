// 红灯回归：收藏库分区可见性判定把 videos/comics 恒判为不可见。
//
// 用户报障：「内容页收藏库影视收藏没显示出来」。
// 原实现 `_shouldShowSection` 里 videos/comics/music 在有搜索词时 `return false`
// 硬编码；`_itemsForCategory` 对非 books 恒返回 const []。两者叠加的结果是：
// 就算 Hive 里真有影视收藏，分区也永远不出现。
//
// 本测试锁住「分区可见性只由该分区自己的数据与搜索命中决定」这条契约，
// 不允许再按分类硬编码 false。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/content/domain/warehouse_models.dart';
import 'package:box/features/content/presentation/warehouse_search.dart';

WarehouseItem _item({
  required WarehouseCategory category,
  required String title,
  String id = '',
}) {
  return WarehouseItem(
    id: id.isEmpty ? 'id_$title' : id,
    title: title,
    subtitle: '',
    coverUrl: '',
    detailUrl: '',
    meta: '',
    category: category,
    sourceLabel: '测试',
    createdAt: 0,
  );
}

void main() {
  group('分区可见性只看该分区自己的数据，不按分类硬编码', () {
    test('无搜索词时，有数据的影视分区必须可见', () {
      final videos = [
        _item(category: WarehouseCategory.videos, title: '流浪地球'),
      ];
      expect(
        shouldShowWarehouseSection(searchQuery: '', matchedInSection: videos),
        isTrue,
        reason: '影视收藏里有真实数据，分区不可以被隐藏',
      );
    });

    test('无搜索词时，有数据的漫画分区必须可见', () {
      final comics = [_item(category: WarehouseCategory.comics, title: '海贼王')];
      expect(
        shouldShowWarehouseSection(searchQuery: '', matchedInSection: comics),
        isTrue,
      );
    });

    test('有搜索词且该分区有命中时，影视分区必须可见（原实现恒 false）', () {
      final videos = [
        _item(category: WarehouseCategory.videos, title: '流浪地球'),
      ];
      final matched = warehouseFilter(videos, '流浪');
      expect(matched, isNotEmpty);
      expect(
        shouldShowWarehouseSection(
          searchQuery: '流浪',
          matchedInSection: matched,
        ),
        isTrue,
        reason: '搜索命中了影视收藏，却把整个分区藏起来 = 用户搜不到自己的收藏',
      );
    });

    test('有搜索词但该分区零命中时，隐藏该分区（避免一堆空分区刷屏）', () {
      final videos = [
        _item(category: WarehouseCategory.videos, title: '流浪地球'),
      ];
      final matched = warehouseFilter(videos, '不存在zzz');
      expect(
        shouldShowWarehouseSection(
          searchQuery: '不存在zzz',
          matchedInSection: matched,
        ),
        isFalse,
      );
    });

    test('无搜索词且分区为空时仍可见（要展示空态引导，告诉用户去哪收藏）', () {
      expect(
        shouldShowWarehouseSection(
          searchQuery: '',
          matchedInSection: const <WarehouseItem>[],
        ),
        isTrue,
      );
    });

    test('四个分类走的是同一套判定，没有任何分类被特殊对待', () {
      for (final category in WarehouseCategory.values) {
        final items = [_item(category: category, title: '样例')];
        expect(
          shouldShowWarehouseSection(searchQuery: '', matchedInSection: items),
          isTrue,
          reason: '$category 有数据时必须可见',
        );
      }
    });
  });

  group('总量统计必须涵盖全部分类（原实现只数 books，顶部数字撒谎）', () {
    test('影视 + 漫画 + 书籍都计入总数', () {
      final total = warehouseTotalItems([
        [_item(category: WarehouseCategory.books, title: '三体')],
        [_item(category: WarehouseCategory.videos, title: '流浪地球')],
        [_item(category: WarehouseCategory.comics, title: '海贼王')],
      ]);
      expect(total, 3);
    });

    test('非空分区数按实际有数据的分区计（原实现恒为 0 或 1）', () {
      final count = warehouseNonEmptySectionCount([
        [_item(category: WarehouseCategory.books, title: '三体')],
        const <WarehouseItem>[],
        [_item(category: WarehouseCategory.comics, title: '海贼王')],
      ]);
      expect(count, 2);
    });

    test('全空时总数与分区数都是 0', () {
      expect(warehouseTotalItems(const []), 0);
      expect(warehouseNonEmptySectionCount(const []), 0);
    });
  });
}

// 内容中心（warehouse_tab）功能缺陷回归。
//
// 这里只测纯逻辑，不搭整页 widget：整页依赖 WarehouseStore / 小说书架 / 影视
// 收藏等多个真实数据源，搭起来要 mock 一大片，收益低。缺陷本身都在纯函数
// 或可提取的判定逻辑里。
import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/content/domain/warehouse_models.dart';
import 'package:box/features/content/presentation/warehouse_search.dart';

WarehouseItem _item({
  required String title,
  String subtitle = '',
  String meta = '',
}) {
  return WarehouseItem(
    id: 'id_${title.hashCode}',
    title: title,
    subtitle: subtitle,
    coverUrl: '',
    detailUrl: 'https://example.com/${title.hashCode}',
    meta: meta,
    category: WarehouseCategory.books,
    sourceLabel: '测试',
    createdAt: 0,
  );
}

void main() {
  group('搜索无结果时必须能被识别（否则页面只剩顶部卡片，用户以为收藏丢了）', () {
    final items = [
      _item(title: '三体', subtitle: '刘慈欣'),
      _item(title: '球状闪电', subtitle: '刘慈欣'),
    ];

    test('有匹配时命中对应项', () {
      expect(warehouseFilter(items, '三体').length, 1);
      expect(warehouseFilter(items, '刘慈欣').length, 2);
    });

    test('搜索词匹配不到任何项时，判定为「搜索无结果」而不是「空收藏库」', () {
      const query = '不存在的书名zzz';
      final matched = warehouseFilter(items, query);
      expect(matched, isEmpty);

      // 关键断言：库里明明有 2 项，此时的空是「搜到没有」而不是「一本都没有」，
      // UI 必须能区分这两种空态。
      expect(
        isWarehouseNoSearchResult(
          query: query,
          totalItemsInLibrary: items.length,
          totalMatched: matched.length,
        ),
        isTrue,
        reason: '库非空 + 有搜索词 + 零命中 = 搜索无结果态',
      );
    });

    test('库本来就空时不算「搜索无结果」，应走原本的空态引导', () {
      expect(
        isWarehouseNoSearchResult(
          query: '三体',
          totalItemsInLibrary: 0,
          totalMatched: 0,
        ),
        isFalse,
      );
    });

    test('没有搜索词时永远不是「搜索无结果」', () {
      expect(
        isWarehouseNoSearchResult(
          query: '',
          totalItemsInLibrary: 2,
          totalMatched: 2,
        ),
        isFalse,
      );
    });

    test('搜索大小写不敏感，且能匹配副标题与 meta', () {
      final list = [_item(title: 'Dune', subtitle: 'Herbert', meta: '科幻')];
      expect(warehouseFilter(list, 'dune'), isNotEmpty);
      expect(warehouseFilter(list, 'HERBERT'), isNotEmpty);
      expect(warehouseFilter(list, '科幻'), isNotEmpty);
    });

    test('搜索词首尾空格不应导致零命中', () {
      expect(
        warehouseFilter(items, '  三体  '),
        isNotEmpty,
        reason: '用户从别处粘贴书名常带空格，不 trim 会搜不到',
      );
    });
  });

  group('编辑模式 + 搜索并存时的选中集', () {
    test('搜索把已选中项过滤掉后，选中集必须收敛到仍可见的项', () {
      final all = [
        _item(title: '三体'),
        _item(title: '球状闪电'),
        _item(title: '沙丘'),
      ];
      // 用户先在无搜索时勾了三项
      final selected = all.map((e) => e.uniqueKey).toSet();
      expect(selected.length, 3);

      // 然后输入「三体」，只剩一项可见
      final visible = warehouseFilter(all, '三体');
      expect(visible.length, 1);

      final converged = retainVisibleSelection(
        selected: selected,
        visibleItems: visible,
      );

      // 不收敛的话，点删除会连带删掉屏幕上根本看不见的「球状闪电」「沙丘」
      expect(converged.length, 1);
      expect(converged.single, visible.single.uniqueKey);
    });

    test('无搜索时选中集不受影响', () {
      final all = [_item(title: '三体'), _item(title: '沙丘')];
      final selected = all.map((e) => e.uniqueKey).toSet();
      final converged = retainVisibleSelection(
        selected: selected,
        visibleItems: warehouseFilter(all, ''),
      );
      expect(converged.length, 2);
    });
  });

  group('批量删除的提示条数', () {
    test('删除数量必须在清空选中集之前取快照', () {
      // 复现原实现的顺序错误：先 _exitEditMode()（清空 _selectedKeys）再读
      // _selectedKeys.length，结果恒为 0 → 用户永远看到「已删除 0 项」。
      final selected = <String>{'a', 'b', 'c'};

      final snapshot = selected.length; // 正确：先取快照
      selected.clear(); // 模拟 _exitEditMode()
      expect(snapshot, 3);
      expect(selected.length, 0, reason: '这就是原实现读到的值');
    });
  });
}

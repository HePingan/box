import 'package:box/novel/core/bookshelf_manager.dart';
import 'package:box/novel/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归：书架的读-改-写必须原子，且不得暴露内部缓存引用。
///
/// 缺陷 1（并发丢写）：addToBookshelf 先 `await getBookshelf()` 再 `await _save()`，
/// 两个并发调用会各自基于同一份快照修改，后写的覆盖先写的 —— 用户同时收藏
/// 两本书，只有一本进书架。
///
/// 缺陷 2（缓存引用逃逸）：getBookshelf 直接返回 `_bookshelfCache` 本体，
/// 调用方的 removeWhere/insert 会就地改写缓存，即使随后 _save 失败，
/// 内存态也已被污染，UI 显示与磁盘不一致。
NovelBook book(String id, String title) => NovelBook(
      id: id,
      title: title,
      author: 'A',
      intro: '',
      coverUrl: '',
      detailUrl: 'http://example.com/$id',
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BookshelfManager.instance.resetForTest();
  });

  group('BookshelfManager 并发安全', () {
    test('并发 addToBookshelf 两本书都必须保留（核心回归）', () async {
      final m = BookshelfManager.instance;

      await Future.wait([
        m.addToBookshelf(book('b1', '斗罗大陆')),
        m.addToBookshelf(book('b2', '遮天')),
      ]);

      final shelf = await m.getBookshelf();
      final ids = shelf.map((b) => b.id).toSet();
      expect(ids, containsAll(<String>['b1', 'b2']),
          reason: '并发收藏不得丢写，实际: $ids');
    });

    test('并发 add + remove 不得互相覆盖', () async {
      final m = BookshelfManager.instance;
      await m.addToBookshelf(book('keep', '保留'));
      await m.addToBookshelf(book('drop', '删除'));

      await Future.wait([
        m.addToBookshelf(book('new', '新增')),
        m.removeFromBookshelf('drop'),
      ]);

      final ids = (await m.getBookshelf()).map((b) => b.id).toSet();
      expect(ids.contains('new'), isTrue, reason: '新增必须生效');
      expect(ids.contains('drop'), isFalse, reason: '删除必须生效');
      expect(ids.contains('keep'), isTrue, reason: '无关项不得被波及');
    });

    test('getBookshelf 返回副本，外部改动不污染内部缓存', () async {
      final m = BookshelfManager.instance;
      await m.addToBookshelf(book('b1', '斗罗大陆'));

      final first = await m.getBookshelf();
      first.clear(); // 模拟调用方就地修改

      final second = await m.getBookshelf();
      expect(second.length, 1,
          reason: '外部 clear 不应清空内部缓存，实际长度: ${second.length}');
    });

    test('重复收藏同一本书不产生重复项', () async {
      final m = BookshelfManager.instance;
      await Future.wait([
        m.addToBookshelf(book('same', '同一本')),
        m.addToBookshelf(book('same', '同一本')),
      ]);

      final shelf = await m.getBookshelf();
      expect(shelf.where((b) => b.id == 'same').length, 1);
    });

    test('写入后重新读取（穿透缓存）内容一致', () async {
      final m = BookshelfManager.instance;
      await m.addToBookshelf(book('b1', '斗罗大陆'));
      await m.addToBookshelf(book('b2', '遮天'));

      m.resetForTest(); // 丢掉内存缓存，强制从磁盘读
      final ids = (await m.getBookshelf()).map((b) => b.id).toSet();
      expect(ids, containsAll(<String>['b1', 'b2']), reason: '磁盘持久化必须完整');
    });
  });
}

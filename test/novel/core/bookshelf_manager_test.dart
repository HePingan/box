import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:box/novel/core/bookshelf_manager.dart';
import 'package:box/novel/core/models.dart';

void main() {
  group('BookshelfManager singleton', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await BookshelfManager.instance.clearBookshelf();
    });

    test('instance is a singleton', () {
      expect(BookshelfManager.instance, same(BookshelfManager.instance));
    });

    test('empty bookshelf returns empty list', () async {
      final books = await BookshelfManager.instance.getBookshelf();
      expect(books, isEmpty);
    });

    test('addToBookshelf adds a book', () async {
      final book = NovelBook(
        id: 'book1',
        title: '测试小说',
        author: '测试作者',
        coverUrl: 'https://example.com/cover.jpg',
        intro: '测试简介',
        detailUrl: '/detail/1',
      );

      await BookshelfManager.instance.addToBookshelf(book);
      final books = await BookshelfManager.instance.getBookshelf();
      expect(books.length, 1);
      expect(books[0].title, '测试小说');
    });

    test('addToBookshelf duplicates are deduplicated by id', () async {
      final book1 = NovelBook(
        id: 'dup1',
        title: '第一版',
        author: '作者',
        coverUrl: '',
        intro: '',
        detailUrl: '/detail/dup',
      );
      final book2 = NovelBook(
        id: 'dup1',
        title: '第二版（更新）',
        author: '作者',
        coverUrl: '',
        intro: '',
        detailUrl: '/detail/dup',
      );

      await BookshelfManager.instance.addToBookshelf(book1);
      await BookshelfManager.instance.addToBookshelf(book2);

      final books = await BookshelfManager.instance.getBookshelf();
      expect(books.length, 1);
      // 最新添加的应在前
      expect(books[0].title, '第二版（更新）');
    });

    test('addToBookshelf deduplicates by detailUrl when id is empty', () async {
      final book1 = NovelBook(
        id: '',
        title: '无名1',
        author: '作者',
        coverUrl: '',
        intro: '',
        detailUrl: '/detail/no-id',
      );
      final book2 = NovelBook(
        id: '',
        title: '无名2',
        author: '作者',
        coverUrl: '',
        intro: '',
        detailUrl: '/detail/no-id',
      );

      await BookshelfManager.instance.addToBookshelf(book1);
      await BookshelfManager.instance.addToBookshelf(book2);

      final books = await BookshelfManager.instance.getBookshelf();
      expect(books.length, 1);
      expect(books[0].title, '无名2');
    });

    test('addToBookshelf inserts new book at front', () async {
      final bookA = NovelBook(
        id: 'a',
        title: 'A',
        author: '',
        coverUrl: '',
        intro: '',
        detailUrl: '/a',
      );
      final bookB = NovelBook(
        id: 'b',
        title: 'B',
        author: '',
        coverUrl: '',
        intro: '',
        detailUrl: '/b',
      );

      await BookshelfManager.instance.addToBookshelf(bookA);
      await BookshelfManager.instance.addToBookshelf(bookB);

      final books = await BookshelfManager.instance.getBookshelf();
      expect(books.length, 2);
      expect(books[0].title, 'B'); // 后添加的 B 在前面
      expect(books[1].title, 'A');
    });

    test('removeFromBookshelf removes by id', () async {
      final book = NovelBook(
        id: 'remove-me',
        title: '待删除',
        author: '',
        coverUrl: '',
        intro: '',
        detailUrl: '/remove',
      );

      await BookshelfManager.instance.addToBookshelf(book);
      expect((await BookshelfManager.instance.getBookshelf()).length, 1);

      await BookshelfManager.instance.removeFromBookshelf('remove-me');
      expect(await BookshelfManager.instance.getBookshelf(), isEmpty);
    });

    test('removeFromBookshelf removes by detailUrl', () async {
      final book = NovelBook(
        id: '',
        title: '按URL删除',
        author: '',
        coverUrl: '',
        intro: '',
        detailUrl: '/detail/remove-by-url',
      );

      await BookshelfManager.instance.addToBookshelf(book);
      expect((await BookshelfManager.instance.getBookshelf()).length, 1);

      await BookshelfManager.instance.removeFromBookshelf(
        '/detail/remove-by-url',
      );
      expect(await BookshelfManager.instance.getBookshelf(), isEmpty);
    });

    test('isInBookshelf returns correct status', () async {
      final book = NovelBook(
        id: 'in-shelf',
        title: '在架',
        author: '',
        coverUrl: '',
        intro: '',
        detailUrl: '/in-shelf',
      );

      expect(await BookshelfManager.instance.isInBookshelf('in-shelf'), false);

      await BookshelfManager.instance.addToBookshelf(book);
      expect(await BookshelfManager.instance.isInBookshelf('in-shelf'), true);

      await BookshelfManager.instance.removeFromBookshelf('in-shelf');
      expect(await BookshelfManager.instance.isInBookshelf('in-shelf'), false);
    });

    test('clearBookshelf removes all books', () async {
      final book = NovelBook(
        id: 'c1',
        title: '清除测试',
        author: '',
        coverUrl: '',
        intro: '',
        detailUrl: '/c1',
      );

      await BookshelfManager.instance.addToBookshelf(book);
      expect((await BookshelfManager.instance.getBookshelf()).length, 1);

      await BookshelfManager.instance.clearBookshelf();
      expect(await BookshelfManager.instance.getBookshelf(), isEmpty);
    });

    test('replaceBookshelf replaces entire shelf', () async {
      final bookOld = NovelBook(
        id: 'old',
        title: '旧书',
        author: '',
        coverUrl: '',
        intro: '',
        detailUrl: '/old',
      );
      await BookshelfManager.instance.addToBookshelf(bookOld);

      final newBooks = <NovelBook>[
        NovelBook(
          id: 'n1',
          title: '新书1',
          author: '',
          coverUrl: '',
          intro: '',
          detailUrl: '/n1',
        ),
        NovelBook(
          id: 'n2',
          title: '新书2',
          author: '',
          coverUrl: '',
          intro: '',
          detailUrl: '/n2',
        ),
      ];
      await BookshelfManager.instance.replaceBookshelf(newBooks);

      final books = await BookshelfManager.instance.getBookshelf();
      expect(books.length, 2);
      expect(books[0].title, '新书1');
      expect(books[1].title, '新书2');
    });
  });

  group('BookshelfManager persistence', () {
    test('data persists in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      await BookshelfManager.instance.clearBookshelf();

      final book = NovelBook(
        id: 'persist',
        title: '持久化测试',
        author: '',
        coverUrl: '',
        intro: '',
        detailUrl: '/persist',
      );
      await BookshelfManager.instance.addToBookshelf(book);

      final books = await BookshelfManager.instance.getBookshelf();
      expect(books.length, 1);
      expect(books[0].id, 'persist');
    });
  });
}

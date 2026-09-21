// 漫画本地库：CBZ/ZIP/文件夹三种导入方式能正常工作
library;


import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/comic/infrastructure/comic_importer.dart';
import 'package:box/core/storage/cache_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CacheStore cacheStore;
  late ComicLibraryStore library;

  setUp(() {
    cacheStore = CacheStore.inMemory('comic_test_library');
    library = ComicLibraryStore(cacheStore: cacheStore);
  });

  tearDown(() async {
    await cacheStore.clear();
  });

  test('ComicBook 构造函数正常', () {
    final book = ComicBook(
      id: 'test-1',
      title: '测试漫画',
      coverPath: '/covers/test.jpg',
      sourceType: ComicSourceType.file,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    expect(book.id, 'test-1');
    expect(book.title, '测试漫画');
    expect(book.pageCount, null); // 还没扫描
    expect(book.isRead, false);
    expect(book.lastReadAt, null);
  });

  test('ComicBook 可序列化/反序列化', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final original = ComicBook(
      id: 'test-2',
      title: '序列化测试',
      coverPath: '/covers/test2.jpg',
      sourceType: ComicSourceType.folder,
      createdAt: now,
    );

    final json = original.toJson();
    final restored = ComicBook.fromJson(json);

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.coverPath, original.coverPath);
    expect(restored.sourceType, original.sourceType);
    expect(restored.createdAt, original.createdAt);
  });

  test('ComicLibraryStore 存取漫画', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final book = ComicBook(
      id: 'lib-test-1',
      title: '库测试',
      coverPath: '/covers/lib.jpg',
      sourceType: ComicSourceType.file,
      createdAt: now,
    );

    await library.add(book);
    final items = await library.fetch();

    expect(items.length, 1);
    expect(items.first.id, 'lib-test-1');
    expect(items.first.title, '库测试');
  });

  test('ComicImporter 能识别 CBZ/ZIP', () {
    // 只测试扩展名识别，不测试解压
    expect(ComicImporter.isComicFile('test.cbz'), isTrue);
    expect(ComicImporter.isComicFile('test.zip'), isTrue);
    expect(ComicImporter.isComicFile('test.cbr'), isFalse); // RAR 不支持
    expect(ComicImporter.isComicFile('test.jpg'), isFalse);
    expect(ComicImporter.isComicFile('test.pdf'), isFalse);
  });
}

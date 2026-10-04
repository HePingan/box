// 漫画本地库：CBZ/ZIP/文件夹三种导入方式能正常工作
library;


import 'package:box/features/comic/domain/comic_library_store.dart';
import 'package:box/features/comic/domain/comic_book.dart';
import 'package:box/features/comic/infrastructure/comic_importer.dart';
import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/content/domain/warehouse_adapters.dart';
import 'package:box/features/content/domain/warehouse_models.dart';
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

  // 用户 2026-10-02 报「漫画点击收藏了，没有进到内容页的漫画收藏」。
  //
  // 存储这条路本来是好的：在线书（sourceType=online）进书架后能原样读回来，
  // 内容页的适配器也认得它（来源写「漫画收藏」、副标题写「在线」，点开进在线页）。
  // 真正缺的是内容页那次**重读**（keep-alive 的页面只在 initState 读一次，
  // 由 app_shell 切 tab 时调 `WarehouseTabState.refreshOnShow()`）。
  // 这条用例钉住"存储与适配"这一半，免得以后有人往这半边找原因。
  test('在线书进书架：读得回来，且内容页适配器认得出它是"在线"', () async {
    await library.add(
      const ComicBook(
        id: 'https://yemancomic.com/comic/zhongguojingqi',
        title: '中国惊奇先生',
        coverPath: 'https://tuer.justpic01pt.com:666/picbed/cover.jpg',
        sourceType: ComicSourceType.online,
        onlineUrl: 'https://yemancomic.com/comic/zhongguojingqi',
        author: '糖小猫',
        createdAt: 1000,
      ),
    );

    final back = await library.fetch();
    expect(back.length, 1, reason: '写进去就该读得回来（条目被 fromJson 丢掉的话，'
        '书架和内容页会同时"什么都没有"）');
    expect(back.single.isOnline, isTrue);
    expect(back.single.onlineUrl, 'https://yemancomic.com/comic/zhongguojingqi');

    final item = warehouseItemFromComicBook(back.single);
    expect(item.category, WarehouseCategory.comics);
    expect(item.sourceLabel, '漫画收藏');
    expect(item.subtitle, contains('在线'), reason: '在线书页数取不到，标签要说"在线"');
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

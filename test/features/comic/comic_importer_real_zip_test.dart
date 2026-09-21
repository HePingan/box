// 真实 CBZ/ZIP 端到端导入验证（不 mock，真的造一个 zip 再解出来）。
//
// 锁住三条真机会出问题的契约：
//   1. 页序必须是自然序：2.jpg 在 10.jpg 之前（字典序会排成 1,10,2...）
//   2. 一本漫画只用一个临时目录，不能每页建一个
//   3. 提取封面不重复解压整包
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:box/features/comic/infrastructure/comic_importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 造一个真实 zip。`entries` 是「入口名 → 内容标记字节」。
/// 用内容标记而不是文件名来验证顺序，因为解出的临时文件名是重写过的。
File _makeZip(Directory dir, String name, Map<String, int> entries) {
  final archive = Archive();
  entries.forEach((entryName, marker) {
    final bytes = List<int>.filled(8, marker);
    archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
  });
  final zipped = ZipEncoder().encode(archive)!;
  return File(p.join(dir.path, name))..writeAsBytesSync(zipped);
}

/// 只给名字、不关心内容标记时的便捷构造。
File _makeZipNames(Directory dir, String name, List<String> names) {
  return _makeZip(dir, name, {
    for (var i = 0; i < names.length; i++) names[i]: i + 1,
  });
}

/// 读回某一页的内容标记。
int _markerOf(String path) => File(path).readAsBytesSync().first;

void main() {
  late Directory work;

  setUp(() {
    work = Directory.systemTemp.createTempSync('comic_importer_e2e_');
  });

  tearDown(() {
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  test('真实 CBZ 能解出全部图片页', () async {
    final zip = _makeZipNames(work, 'book.cbz', [
      '001.jpg',
      '002.jpg',
      '003.png',
      'ComicInfo.xml', // 非图片，必须被过滤
    ]);

    final pages = await ComicImporter.extractPages(zip.path);

    expect(pages.length, 3, reason: '只应提取 3 个图片页，xml 要过滤掉');
    for (final page in pages) {
      expect(File(page).existsSync(), isTrue, reason: '解出的页必须真的落盘');
    }
  });

  test('页序按自然序，不能是字典序', () async {
    // 故意乱序写进压缩包，标记值即期望的最终页序
    final zip = _makeZip(work, 'natural.cbz', {
      '10.jpg': 3,
      '1.jpg': 1,
      '20.jpg': 5,
      '11.jpg': 4,
      '2.jpg': 2,
    });

    final pages = await ComicImporter.extractPages(zip.path);
    expect(pages.length, 5);

    expect(
      pages.map(_markerOf).toList(),
      [1, 2, 3, 4, 5],
      reason: '自然序应为 1,2,10,11,20；字典序会得到 1,10,11,2,20，页序就乱了',
    );

    // 解出的文件名前缀应与最终顺序一致，便于排查
    expect(
      pages.map(ComicImporter.debugPageOrderKey).toList(),
      [0, 1, 2, 3, 4],
    );
  });

  test('一本漫画只用一个临时目录', () async {
    final zip = _makeZipNames(
      work,
      'many.cbz',
      List.generate(12, (i) => '${i + 1}.jpg'),
    );

    final pages = await ComicImporter.extractPages(zip.path);
    expect(pages.length, 12);

    final dirs = pages.map((path) => p.dirname(path)).toSet();
    expect(
      dirs.length,
      1,
      reason: '每页建一个临时目录会在大部头漫画上炸出上百个目录',
    );
  });

  test('封面优先取名字里带 cover 的条目', () async {
    final zip = _makeZipNames(work, 'cover.cbz', [
      '001.jpg',
      'cover.png',
      '002.jpg',
    ]);

    final cover = await ComicImporter.extractCover(zip.path);
    expect(cover, isNotNull);
    expect(p.basename(cover!).toLowerCase(), contains('cover'));
    expect(File(cover).existsSync(), isTrue);
  });

  test('没有 cover 条目时封面回落到第一页', () async {
    final zip =
        _makeZipNames(work, 'nocover.cbz', ['003.jpg', '001.jpg', '002.jpg']);

    final cover = await ComicImporter.extractCover(zip.path);
    final pages = await ComicImporter.extractPages(zip.path);

    expect(cover, isNotNull);
    expect(
      p.basename(cover!),
      p.basename(pages.first),
      reason: '回落封面应当就是排序后的第一页',
    );
  });

  test('空 zip 与无图片 zip 返回空列表而不是抛异常', () async {
    final empty = _makeZipNames(work, 'empty.cbz', []);
    final noImage = _makeZipNames(work, 'noimg.cbz', ['readme.txt', 'info.xml']);

    expect(await ComicImporter.extractPages(empty.path), isEmpty);
    expect(await ComicImporter.extractPages(noImage.path), isEmpty);
    expect(await ComicImporter.extractCover(noImage.path), isNull);
  });

  test('损坏文件不应崩，抛出可捕获的异常', () async {
    final broken = File(p.join(work.path, 'broken.cbz'))
      ..writeAsBytesSync([0, 1, 2, 3, 4, 5]);

    expect(
      () => ComicImporter.extractPages(broken.path),
      throwsA(isA<Exception>()),
    );
  });

  test('文件夹导入按自然序返回图片', () async {
    final folder = Directory(p.join(work.path, 'folder_comic'))
      ..createSync(recursive: true);
    for (final name in ['1.jpg', '2.jpg', '10.jpg', 'note.txt']) {
      File(p.join(folder.path, name)).writeAsBytesSync([1, 2, 3]);
    }

    final pages = await ComicImporter.extractPagesFromFolder(folder.path);

    expect(pages.length, 3, reason: 'txt 要被过滤');
    expect(
      pages.map((path) => p.basename(path)).toList(),
      ['1.jpg', '2.jpg', '10.jpg'],
      reason: '文件夹导入同样要自然序',
    );
  });

  test('isComicFile 认得 cbz/zip，大小写不敏感', () {
    expect(ComicImporter.isComicFile('/a/b.cbz'), isTrue);
    expect(ComicImporter.isComicFile('/a/b.CBZ'), isTrue);
    expect(ComicImporter.isComicFile('/a/b.zip'), isTrue);
    expect(ComicImporter.isComicFile('/a/b.rar'), isFalse);
    expect(ComicImporter.isComicFile('/a/b.jpg'), isFalse);
  });
}

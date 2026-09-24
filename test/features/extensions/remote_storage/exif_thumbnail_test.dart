// EXIF 内嵌缩略图解析（283 D1）。
//
// 夹具是**真实结构**的 JPEG（PIL 编码写入的 APP1/Exif），断言用的是内嵌缩略图的
// 真值字节（`kExifEmbeddedThumb`），不是"再解析一次看两边一样"这种自证。
//
// 边界情况是重点：输入永远是"网络前缀"，可能在任意位置被截断。

import 'dart:typed_data';

import 'package:box/features/extensions/plugins/remote_storage/domain/exif_thumbnail.dart';
import 'package:flutter_test/flutter_test.dart';

import 'exif_fixtures.dart';
import 'fakes.dart';

/// 造一个最小的"合法 JPEG 头 + APP1/Exif(TIFF)"：用于越界与畸形用例。
Uint8List syntheticJpeg({
  required List<int> ifd0Entries,
  required int ifd0NextIfd,
  int tiffLength = 64,
}) {
  final tiff = <int>[];
  tiff.addAll([0x49, 0x49, 42, 0, 8, 0, 0, 0]); // II, magic 42, IFD0 @8
  tiff.addAll([ifd0Entries.length ~/ 12, 0]);
  tiff.addAll(ifd0Entries);
  tiff.addAll([
    ifd0NextIfd & 0xFF,
    (ifd0NextIfd >> 8) & 0xFF,
    (ifd0NextIfd >> 16) & 0xFF,
    (ifd0NextIfd >> 24) & 0xFF,
  ]);
  while (tiff.length < tiffLength) {
    tiff.add(0);
  }
  final payload = <int>[...'Exif'.codeUnits, 0, 0, ...tiff];
  return Uint8List.fromList([
    0xFF, 0xD8, // SOI
    0xFF, 0xE1, // APP1
    ((payload.length + 2) >> 8) & 0xFF, (payload.length + 2) & 0xFF,
    ...payload,
    0xFF, 0xD9, // EOI
  ]);
}

/// 一个 IFD 条目（12 字节）。
List<int> ifdEntry(int tag, int type, int count, int value) => [
  tag & 0xFF, (tag >> 8) & 0xFF,
  type & 0xFF, (type >> 8) & 0xFF,
  count & 0xFF, (count >> 8) & 0xFF, (count >> 16) & 0xFF, (count >> 24) & 0xFF,
  value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF, (value >> 24) & 0xFF,
];

void main() {
  group('真实样本（PIL 写入的 EXIF）', () {
    test('取出内嵌缩略图：字节与真值完全一致，并读到 Orientation', () {
      final result = parseExifThumbnail(kExifJpeg);

      expect(result, isNotNull, reason: '样本里 IFD1 有内嵌缩略图');
      expect(
        result!.bytes,
        kExifEmbeddedThumb,
        reason: '取出的必须是内嵌的那张 JPEG，一字不差',
      );
      expect(result.bytes[0], 0xFF);
      expect(result.bytes[1], 0xD8, reason: '内嵌缩略图本身是 JPEG');
      expect(result.orientation, 6, reason: 'IFD0 里写了 Orientation=6');
    });

    test('只给文件开头一段（前缀）也能取到——这正是"大图缩略图"的前提', () {
      // 模拟真实路径：只读前 256KB（样本只有 1.7KB，所以给前 1KB 更严格）
      final prefix = Uint8List.sublistView(kExifJpeg, 0, 1024);
      final result = parseExifThumbnail(prefix);
      expect(result, isNotNull);
      expect(result!.bytes, kExifEmbeddedThumb);
    });

    test('前缀在缩略图中间被截断 → 返回 null（不返回半张图）', () {
      // 缩略图字节从 TIFF 偏移 122 开始、长 645；这里只给到缩略图中途
      final truncated = Uint8List.sublistView(kExifJpeg, 0, 400);
      expect(parseExifThumbnail(truncated), isNull);
    });

    test('APP1 不带 Exif\\0\\0 前缀（少数写入器）同样能解析', () {
      final result = parseExifThumbnail(kExifJpegNoPrefix);
      expect(result, isNotNull);
      expect(result!.bytes, kExifEmbeddedThumb);
    });

    test('没有 EXIF 的 JPEG → null', () {
      expect(parseExifThumbnail(kJpegWithoutExif), isNull);
      expect(parseExifOrientation(kJpegWithoutExif), isNull);
    });

    test('不是 JPEG（PNG）→ null', () {
      expect(parseExifThumbnail(kTinyPng), isNull);
    });
  });

  group('畸形输入（网络前缀随时可能被切断/损坏）', () {
    test('空 / 太短 → null，不抛异常', () {
      for (final data in [
        Uint8List(0),
        Uint8List.fromList([0xFF]),
        Uint8List.fromList([0xFF, 0xD8]),
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1]),
      ]) {
        expect(parseExifThumbnail(data), isNull);
      }
    });

    test('段长度字段超过数据长度（前缀被截断在 EXIF 段内）→ null', () {
      final full = kExifJpeg;
      final cut = Uint8List.sublistView(full, 0, 30); // APP1 声明长度远大于 30
      expect(parseExifThumbnail(cut), isNull);
    });

    test('IFD1 偏移指向数据之外 → null（不越界读）', () {
      final data = syntheticJpeg(
        ifd0Entries: ifdEntry(0x0112, 3, 1, 1),
        ifd0NextIfd: 0x7FFFFFFF, // 荒谬的 IFD1 偏移
      );
      expect(parseExifThumbnail(data), isNull);
    });

    test('IFD1 里缩略图长度超过可用字节 → null', () {
      // IFD0（1 条）→ IFD1 @26；IFD1 声明 offset=40、length=0xFFFF（远超数据）
      final ifd0 = ifdEntry(0x0112, 3, 1, 1);
      final ifd1 = <int>[
        2, 0, // 2 条
        ...ifdEntry(0x0201, 4, 1, 40),
        ...ifdEntry(0x0202, 4, 1, 0xFFFF),
        0, 0, 0, 0,
      ];
      final tiff = <int>[
        0x49, 0x49, 42, 0, 8, 0, 0, 0,
        1, 0, ...ifd0, 26, 0, 0, 0, // IFD0 → next=26
        ...ifd1,
      ];
      final payload = <int>[...'Exif'.codeUnits, 0, 0, ...tiff];
      final data = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE1,
        ((payload.length + 2) >> 8) & 0xFF, (payload.length + 2) & 0xFF,
        ...payload, 0xFF, 0xD9,
      ]);
      expect(parseExifThumbnail(data), isNull);
    });

    test('IFD1 指向的字节不是 JPEG（不是 SOI）→ null', () {
      // 缩略图 offset 指向全 0 区域
      final tiff = <int>[
        0x49, 0x49, 42, 0, 8, 0, 0, 0,
        1, 0, ...ifdEntry(0x0112, 3, 1, 1), 26, 0, 0, 0,
        2, 0,
        ...ifdEntry(0x0201, 4, 1, 56),
        ...ifdEntry(0x0202, 4, 1, 4),
        0, 0, 0, 0,
      ];
      while (tiff.length < 60) {
        tiff.add(0);
      }
      final payload = <int>[...'Exif'.codeUnits, 0, 0, ...tiff];
      final data = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE1,
        ((payload.length + 2) >> 8) & 0xFF, (payload.length + 2) & 0xFF,
        ...payload, 0xFF, 0xD9,
      ]);
      expect(parseExifThumbnail(data), isNull);
    });

    test('大端（MM）TIFF 也能读', () {
      // 大端：MM\0* + IFD0@8；IFD0 1 条 Orientation=1；next IFD=26
      final tiff = <int>[
        0x4D, 0x4D, 0, 42, 0, 0, 0, 8,
        0, 1, // 1 条
        0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 1, 0, 0, // Orientation=1
        0, 0, 0, 26, // next IFD
        0, 2, // IFD1: 2 条
        0x02, 0x01, 0, 4, 0, 0, 0, 1, 0, 0, 0, 56,
        0x02, 0x02, 0, 4, 0, 0, 0, 1, 0, 0, 0, 4,
        0, 0, 0, 0,
      ];
      tiff.addAll([0xFF, 0xD8, 0xFF, 0xD9]); // 4 字节"内嵌 JPEG"（SOI+EOI）
      final payload = <int>[...'Exif'.codeUnits, 0, 0, ...tiff];
      final data = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE1,
        ((payload.length + 2) >> 8) & 0xFF, (payload.length + 2) & 0xFF,
        ...payload, 0xFF, 0xD9,
      ]);

      final result = parseExifThumbnail(data);
      expect(result, isNotNull, reason: '大端字节序也要能读');
      expect(result!.bytes, [0xFF, 0xD8, 0xFF, 0xD9]);
      expect(result.orientation, 1);
    });
  });
}

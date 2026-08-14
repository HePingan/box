import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/pages/reader/reader_progress_locator.dart';

void main() {
  group('computePageStartOffsets', () {
    test('empty pages', () {
      expect(computePageStartOffsets([], 'any'), isEmpty);
    });

    test('single page', () {
      final pages = ['Hello'];
      final content = 'Hello';
      expect(computePageStartOffsets(pages, content), [0]);
    });

    test('multiple consecutive pages', () {
      final content = 'ABCDEFGHIJ';
      final pages = ['ABC', 'DEF', 'GHI', 'J'];
      final offsets = computePageStartOffsets(pages, content);
      expect(offsets, [0, 3, 6, 9]);
    });

    test('pages with skipped newlines', () {
      // 分页器会跳过页首换行，所以 "BCD" 实际在原文 offset=4
      final content = 'ABC\n\nBCD';
      final pages = ['ABC', 'BCD'];
      final offsets = computePageStartOffsets(pages, content);
      expect(offsets, [0, 5]);
    });

    test('page not found fallback', () {
      // 页内容在原文中不存在 —— 理论上不该发生，但要保证单调不减
      final content = 'ABC';
      final pages = ['ABC', 'XYZ', 'DEF'];
      final offsets = computePageStartOffsets(pages, content);
      expect(offsets[0], 0);
      expect(offsets[1], 0); // XYZ 找不到，回退为前一页偏移
      expect(offsets[2], 0); // DEF 找不到，同样回退
    });

    test('empty page', () {
      final content = 'ABCDEF';
      final pages = ['ABC', '', 'DEF'];
      final offsets = computePageStartOffsets(pages, content);
      expect(offsets[0], 0);
      expect(offsets[1], 3); // 空页保持游标位置
      expect(offsets[2], 3);
    });
  });

  group('locatePageForCharOffset', () {
    test('empty offsets', () {
      expect(locatePageForCharOffset([], 100), 0);
    });

    test('offset before first page', () {
      expect(locatePageForCharOffset([10, 20, 30], 5), 0);
    });

    test('exact match', () {
      expect(locatePageForCharOffset([0, 10, 20], 20), 2);
    });

    test('between pages', () {
      // offset=15 落在第 1 页（start=10）和第 2 页（start=20）之间，取靠前的
      expect(locatePageForCharOffset([0, 10, 20], 15), 1);
    });

    test('after last page', () {
      expect(locatePageForCharOffset([0, 10, 20], 999), 2);
    });

    test('monotonic offsets', () {
      final offsets = [0, 0, 5, 5, 10]; // 有重复 —— 来自空页或定位失败的回退
      expect(locatePageForCharOffset(offsets, 0), 0); // charOffset <= first 短路返回 0
      expect(locatePageForCharOffset(offsets, 5), 3); // 取最后一个 <= 5 的
      expect(locatePageForCharOffset(offsets, 7), 3);
      expect(locatePageForCharOffset(offsets, 10), 4);
    });
  });

  group('charOffsetForPage', () {
    test('page index out of bounds', () {
      final pages = ['AB', 'CD'];
      final content = 'ABCD';
      expect(charOffsetForPage(pages, content, -1), isNull);
      expect(charOffsetForPage(pages, content, 2), isNull);
    });

    test('valid page index', () {
      final pages = ['AB', 'CD', 'EF'];
      final content = 'ABCDEF';
      expect(charOffsetForPage(pages, content, 0), 0);
      expect(charOffsetForPage(pages, content, 1), 2);
      expect(charOffsetForPage(pages, content, 2), 4);
    });
  });

  group('end-to-end: save and restore', () {
    test('simulate save at page 2, restore after re-paginate', () {
      final content = 'ABCDEFGHIJKLMNOP';
      final originalPages = ['ABCD', 'EFGH', 'IJKL', 'MNOP'];

      // 用户在第 2 页（0-based），即 "IJKL"
      final savedCharOffset = charOffsetForPage(originalPages, content, 2);
      expect(savedCharOffset, 8);

      // 用户改了字号，重新分页后页边界不同
      final newPages = ['ABC', 'DEFGHI', 'JKLMN', 'OP'];
      final offsets = computePageStartOffsets(newPages, content);
      // offsets = [0, 3, 9, 14]

      // 恢复时用字符偏移 8 定位，二分找最后一个 <= 8 的，应该是 index=1（offset=3）
      final restoredPage = locatePageForCharOffset(offsets, savedCharOffset!);
      expect(restoredPage, 1); // "DEFGHI" 包含 offset=8 的字符 'I'
      expect(newPages[restoredPage], 'DEFGHI');
    });

    test('simulate old progress without charOffset', () {
      // 旧进度只有页索引 1（"EFGH"），新分页后边界变了，
      // 页索引 1 现在指向 "DEFGHI"，内容已不同 —— 这就是旧逻辑的缺陷。
      // 但有了 charOffset 后，应该定位到原文 offset=4 附近。
      final content = 'ABCDEFGHIJKLMNOP';
      final newPages = ['ABC', 'DEFGHI', 'JKLMN', 'OP'];
      final offsets = computePageStartOffsets(newPages, content);

      // 假设旧逻辑保存的是页索引 1，对应原页 "EFGH" 起始 offset=4
      final restoredPage = locatePageForCharOffset(offsets, 4);
      expect(restoredPage, 1); // 应定位到新分页的 "DEFGHI"
    });
  });
}

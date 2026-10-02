// 自动加载下一话的封顶规则（按张数，不按话数）。
//
// 为什么要一条纯单测而不是搭一个"接满 60 张"的阅读器场景：那种用例要造 6 话 × 10 张
// 以上的假书，阅读器里每张图都是一个 FutureBuilder + 取图，跑起来又慢又容易挂
// （2026-10-02 实测：那样写的用例 8 分钟没跑完）。规则本身这么简单，单独测最实在。
library;

import 'package:box/features/comic/domain/comic_auto_append.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('自动接话的封顶（按张数）', () {
    test('没接过：还能接着接', () {
      expect(canAutoAppendMore(0), isTrue);
    });

    test('差一张到顶：还能接（最后一话要能接上）', () {
      expect(canAutoAppendMore(kMaxAutoAppendImages - 1), isTrue);
    });

    test('正好到顶：不再接', () {
      expect(canAutoAppendMore(kMaxAutoAppendImages), isFalse);
    });

    test('超了：更不该接', () {
      expect(canAutoAppendMore(kMaxAutoAppendImages + 30), isFalse);
    });

    test('短话能多接几话（10 张一话 → 接 6 话才到顶）', () {
      var images = 0;
      var chapters = 0;
      while (canAutoAppendMore(images)) {
        images += 10;
        chapters++;
      }
      expect(chapters, 6, reason: '6 话 × 10 张 = 60 张，正好到顶');
    });

    test('长话只会接很少几话（200 张一话 → 一话就到顶，第二话不接）', () {
      var images = 0;
      var chapters = 0;
      while (canAutoAppendMore(images)) {
        images += 200;
        chapters++;
      }
      expect(chapters, 1, reason: '接一话就 200 张，够多了');
    });
  });
}

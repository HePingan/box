import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/pages/reader/reader_layout_metrics.dart';

/// 小窗里第 0 页正文被 46dp 标题块挤成零高的回归测试。
///
/// ## 真实取证
///
/// 红米 K80 小窗实测逻辑尺寸 101.7 x 162.7 dp（录屏逐帧像素反推）。
/// `_buildPagedReaderView` 扣掉 padding 后：
///
/// ```
/// topPad=24: firstTextHeight = 162.7 - (24+8+8) - 46 - 24 - 14 = 38.7dp
/// ```
///
/// 而 `ReaderPagedView` 第 0 页会先塞一个**固定 46dp 高**的大标题
/// （reader_paged_view.dart:122-137，fontSize 26），Column 里剩给
/// `Expanded` 正文的高度是 `38.7 - 46 < 0` → 正文被压成零高，一个字都画不出。
///
/// 第 1 页起标题块只有 24dp（fontSize 10），所以「翻一页就有字了」——
/// 这与用户「不刷新」的描述一致：停在第 0 页时永远空白。
///
/// ## 不变式
///
/// 标题块高度必须让位给正文：可用高度不足时收缩甚至隐藏标题，
/// 保证正文永远拿到 > 0 的高度。
void main() {
  group('标题块不能把正文挤成零高', () {
    test('小窗（38.7dp 可用）第 0 页仍要留出正文高度', () {
      final m = ReaderLayoutMetrics.resolve(
        availableHeight: 38.7,
        isFirstPage: true,
      );
      expect(m.textHeight, greaterThan(0),
          reason: '正文高度 <=0 → 第 0 页一个字都画不出，就是小窗空白的直接原因');
      expect(m.titleHeight, lessThan(46.0),
          reason: '可用高度只有 38.7dp 时还占满 46dp 标题，正文必然为负');
    });

    test('极端矮窗（10dp）也要保正文，标题可以完全让位', () {
      final m = ReaderLayoutMetrics.resolve(
        availableHeight: 10.0,
        isFirstPage: true,
      );
      expect(m.textHeight, greaterThan(0));
      expect(m.titleHeight, 0.0, reason: '空间实在不够时标题应彻底隐藏，把高度全给正文');
    });

    test('正常大窗第 0 页保持原有 46dp 大标题', () {
      final m = ReaderLayoutMetrics.resolve(
        availableHeight: 700.0,
        isFirstPage: true,
      );
      expect(m.titleHeight, 46.0, reason: '大窗不能改变既有观感');
      expect(m.textHeight, 700.0 - 46.0);
    });

    test('非首页标题块是 24dp，矮窗下同样要让位', () {
      final big = ReaderLayoutMetrics.resolve(
        availableHeight: 700.0,
        isFirstPage: false,
      );
      expect(big.titleHeight, 24.0);
      expect(big.textHeight, 700.0 - 24.0);

      final tiny = ReaderLayoutMetrics.resolve(
        availableHeight: 20.0,
        isFirstPage: false,
      );
      expect(tiny.textHeight, greaterThan(0));
      expect(tiny.titleHeight, lessThan(24.0));
    });

    test('可用高度非法（<=0）时不产生负数尺寸', () {
      for (final h in <double>[0.0, -30.0]) {
        final m = ReaderLayoutMetrics.resolve(
          availableHeight: h,
          isFirstPage: true,
        );
        expect(m.titleHeight, greaterThanOrEqualTo(0.0), reason: 'h=$h');
        expect(m.textHeight, greaterThanOrEqualTo(0.0),
            reason: 'h=$h 不能返回负高度，否则 Flutter 直接抛布局异常');
      }
    });

    test('标题 + 正文永不超过可用高度（不溢出）', () {
      for (final h in <double>[38.7, 60.0, 100.7, 122.7, 300.0, 700.0]) {
        for (final first in <bool>[true, false]) {
          final m = ReaderLayoutMetrics.resolve(
            availableHeight: h,
            isFirstPage: first,
          );
          expect(
            m.titleHeight + m.textHeight,
            lessThanOrEqualTo(h + 0.001),
            reason: 'h=$h first=$first 溢出会触发 RenderFlex overflow',
          );
        }
      }
    });
  });

  // 加固改动的等价性闸门：reader_page.dart 原本硬编码 46/24 算正文高，
  // 现在改走 ReaderLayoutMetrics。大窗下必须逐值一致，否则会让所有用户的
  // 分页悄悄重排（阅读进度跳位）。
  group('改走 metrics 后大窗分页高度不能变', () {
    double legacyTextHeight(double maxHeight, double topPad, bool isFirst) {
      final paddingTotal = topPad + 8.0 + 8.0;
      final title = isFirst ? 46.0 : 24.0;
      return maxHeight - paddingTotal - title - 24.0 - 14.0;
    }

    double currentTextHeight(double maxHeight, double topPad, bool isFirst) {
      final paddingTotal = topPad + 8.0 + 8.0;
      final avail = maxHeight - paddingTotal - 24.0 - 14.0;
      return ReaderLayoutMetrics.resolve(
        availableHeight: avail,
        isFirstPage: isFirst,
      ).textHeight;
    }

    test('常见机型与 K80 小窗上新旧公式逐值一致', () {
      const cases = <List<double>>[
        [904.0, 24.0], // iQOO / K80 全屏
        [844.0, 47.0], // 刘海屏
        [1280.0, 24.0], // 平板
        [162.7, 0.0], // K80 小窗
        [162.7, 24.0], // K80 小窗带状态栏
        [200.0, 24.0],
        [300.0, 0.0],
      ];
      for (final c in cases) {
        for (final isFirst in [true, false]) {
          final legacy = legacyTextHeight(c[0], c[1], isFirst);
          expect(legacy, greaterThan(0), reason: '用例选错了：这一档老公式本来就不可用');
          expect(
            currentTextHeight(c[0], c[1], isFirst),
            closeTo(legacy, 0.001),
            reason: 'H=${c[0]} topPad=${c[1]} isFirst=$isFirst 分页高度变了，'
                '会导致线上用户分页重排',
          );
        }
      }
    });

    test('老公式算出负高的极矮窗，新算法给出正数正文高', () {
      // 80dp 窗口：老公式首页 -28dp、非首页 -6dp → 永久 spinner。
      // 新算法此时 availableHeight 本身只有 2dp，minTextHeight(16) 是
      // 「够的时候要保住」而非「凭空造高度」，所以标题完全让位、
      // 正文拿到全部可用高度 2dp —— 关键是正数，不再触发 spinner 守卫。
      const avail = 80.0 - (24.0 + 8.0 + 8.0) - 24.0 - 14.0;
      expect(avail, lessThan(ReaderLayoutMetrics.minTextHeight),
          reason: '这一档可用高度本就不足 minTextHeight，用例前提');

      for (final isFirst in [true, false]) {
        expect(legacyTextHeight(80.0, 24.0, isFirst), lessThan(0));

        final now = currentTextHeight(80.0, 24.0, isFirst);
        expect(now, greaterThan(0), reason: '正数才不会被 spinner 守卫拦下');
        expect(now, closeTo(avail, 0.001), reason: '标题应完全让位，正文吃满可用高度');
      }
    });

    test('可用高度够时 minTextHeight 才必须保住', () {
      // 120dp 窗口：avail = 42dp > 16dp，标题让位到 26dp，正文拿 16dp
      const avail = 120.0 - (24.0 + 8.0 + 8.0) - 24.0 - 14.0;
      expect(avail, greaterThan(ReaderLayoutMetrics.minTextHeight));

      final m = ReaderLayoutMetrics.resolve(
        availableHeight: avail,
        isFirstPage: true,
      );
      expect(m.textHeight,
          greaterThanOrEqualTo(ReaderLayoutMetrics.minTextHeight));
      expect(m.titleHeight, lessThan(ReaderLayoutMetrics.firstPageTitleHeight),
          reason: '46dp 放不下，标题必须缩');
      expect(m.titleHeight + m.textHeight, closeTo(avail, 0.001));
    });
  });
}


import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/local_tools/domain/local_tool_device.dart' as d;

/// 刻度尺精度：真实 dpi 换算 + 「不可信 dpi」的降级判定。
void main() {
  group('真实 dpi 换算', () {
    test('160dpi 下 160px 正好 1 英寸 = 25.4mm', () {
      expect(d.pxToMillimetersWithDpi(160, 160), closeTo(25.4, 0.001));
    });

    test('440dpi 下换算（常见 1080p 屏）', () {
      // 1080px / 440dpi ≈ 2.4545 英寸 ≈ 62.35mm
      expect(d.pxToMillimetersWithDpi(1080, 440), closeTo(62.35, 0.01));
    });

    test('dpi 为 0 报错而不是返回 Infinity', () {
      expect(() => d.pxToMillimetersWithDpi(100, 0),
          throwsA(isA<d.DeviceToolError>()));
      expect(() => d.pxToMillimetersWithDpi(100, -1),
          throwsA(isA<d.DeviceToolError>()));
    });
  });

  group('dpi 可信度判定', () {
    test('真实 xdpi 与 densityDpi 明显不同 → 可信', () {
      const m = d.ScreenMetrics(
        widthPx: 1080,
        heightPx: 2400,
        xdpi: 394.7,
        ydpi: 395.2,
        densityDpi: 440,
      );
      expect(m.isDpiTrustworthy, isTrue);
    });

    test('xdpi == densityDpi（厂商没填真实值）→ 不可信', () {
      const m = d.ScreenMetrics(
        widthPx: 1080,
        heightPx: 2400,
        xdpi: 420.0,
        ydpi: 420.0,
        densityDpi: 420,
      );
      expect(m.isDpiTrustworthy, isFalse);
    });

    test('xdpi 只差 1（四舍五入痕迹）→ 不可信', () {
      const m = d.ScreenMetrics(
        widthPx: 1080,
        heightPx: 2400,
        xdpi: 421.0,
        ydpi: 421.0,
        densityDpi: 420,
      );
      expect(m.isDpiTrustworthy, isFalse);
    });

    test('dpi 为 0（平台没报）→ 不可信', () {
      const m = d.ScreenMetrics(
        widthPx: 1080,
        heightPx: 2400,
        xdpi: 0,
        ydpi: 0,
        densityDpi: 440,
      );
      expect(m.isDpiTrustworthy, isFalse);
    });
  });

  group('dpi 选取与降级', () {
    test('可信时用真实 xdpi 且标记 isReal', () {
      const m = d.ScreenMetrics(
        widthPx: 1080,
        heightPx: 2400,
        xdpi: 394.7,
        ydpi: 395.2,
        densityDpi: 440,
      );
      final r = d.resolveDpi(metrics: m, fallbackDpr: 2.75);
      expect(r.isReal, isTrue);
      expect(r.dpi, closeTo(394.7, 0.001));
    });

    test('不可信时退回估算值并标记 isReal=false（UI 要注明估算）', () {
      const m = d.ScreenMetrics(
        widthPx: 1080,
        heightPx: 2400,
        xdpi: 420.0,
        ydpi: 420.0,
        densityDpi: 420,
      );
      final r = d.resolveDpi(metrics: m, fallbackDpr: 2.625);
      expect(r.isReal, isFalse);
      expect(r.dpi, closeTo(420.0, 0.001)); // 2.625 * 160
    });

    test('平台通道拿不到（null）时退回估算值', () {
      final r = d.resolveDpi(metrics: null, fallbackDpr: 2.75);
      expect(r.isReal, isFalse);
      expect(r.dpi, closeTo(440.0, 0.001));
    });

    test('退回的值与实际 true dpi 不同 —— 这就是「估算」的代价', () {
      // 真机 xdpi 394.7，估算给 440 → 量同一条边会偏小约 10%。
      const m = d.ScreenMetrics(
        widthPx: 1080,
        heightPx: 2400,
        xdpi: 394.7,
        ydpi: 395.2,
        densityDpi: 440,
      );
      final real = d.resolveDpi(metrics: m, fallbackDpr: 2.75);
      final est = d.resolveDpi(metrics: null, fallbackDpr: 2.75);
      final mmReal = d.pxToMillimetersWithDpi(1080, real.dpi);
      final mmEst = d.pxToMillimetersWithDpi(1080, est.dpi);
      expect((mmReal - mmEst).abs(), greaterThan(6)); // 差 6mm 以上
    });
  });
}

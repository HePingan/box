import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/core/models.dart';

void main() {
  group('ReaderSettings.copyWith 字体族可以显式清空', () {
    test('未传 fontFamily 时保留原值', () {
      const s = ReaderSettings(fontFamily: 'serif');
      expect(s.copyWith(fontSize: 22).fontFamily, 'serif');
    });

    test('显式传 null 时回到系统默认（回归：以前无法从衬线体切回系统默认）', () {
      const s = ReaderSettings(fontFamily: 'serif');
      expect(s.copyWith(fontFamily: null).fontFamily, isNull);
    });

    test('传新字体族时正常覆盖', () {
      const s = ReaderSettings(fontFamily: 'serif');
      expect(s.copyWith(fontFamily: 'monospace').fontFamily, 'monospace');
    });
  });

  group('ReaderSettings 序列化', () {
    test('prefetchAheadPx 参与往返序列化（回归：以前会丢失）', () {
      const s = ReaderSettings(prefetchAheadPx: 3500);
      final round = ReaderSettings.fromJson(s.toJson());
      expect(round.prefetchAheadPx, 3500);
    });

    test('缺字段时回落到默认值', () {
      final s = ReaderSettings.fromJson(<String, dynamic>{});
      expect(s.prefetchAheadPx, 2000.0);
      expect(s.fontFamily, isNull);
      expect(s.letterSpacing, 0.0);
    });

    test('全字段往返后与原对象相等', () {
      const s = ReaderSettings(
        fontSize: 24,
        lineHeight: 2.2,
        themeMode: ReaderThemeMode.dark,
        brightness: 0.6,
        keepScreenOn: true,
        enableHaptic: false,
        letterSpacing: 0.4,
        fontFamily: 'monospace',
        prefetchAheadPx: 1500,
      );
      expect(ReaderSettings.fromJson(s.toJson()), s);
    });
  });
}

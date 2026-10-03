import 'package:box/video/widgets/player/player_gesture_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlayerGestureMath', () {
    test('向上拖变大，向下拖变小（与 Flutter 的 deltaY 方向一致）', () {
      final up = PlayerGestureMath.applyDelta(
        current: 0.5,
        deltaY: -40, // 手指向上
        trackHeight: 400,
      );
      final down = PlayerGestureMath.applyDelta(
        current: 0.5,
        deltaY: 40,
        trackHeight: 400,
      );
      expect(up, greaterThan(0.5));
      expect(down, lessThan(0.5));
    });

    test('拖 0.8 屏 ≈ 走满量程（travelRatio=1.25 的意义）', () {
      final value = PlayerGestureMath.applyDelta(
        current: 0.0,
        deltaY: -320, // 屏高 400 * 0.8
        trackHeight: 400,
      );
      expect(value, closeTo(1.0, 0.001));
    });

    test('结果恒在 0..1（拖过头也不会越界）', () {
      expect(
        PlayerGestureMath.applyDelta(
          current: 0.9,
          deltaY: -1000,
          trackHeight: 400,
        ),
        1.0,
      );
      expect(
        PlayerGestureMath.applyDelta(
          current: 0.1,
          deltaY: 1000,
          trackHeight: 400,
        ),
        0.0,
      );
    });

    test('拿不到高度（0/NaN）时数值不动，不抛不跳', () {
      expect(
        PlayerGestureMath.applyDelta(
          current: 0.42,
          deltaY: -50,
          trackHeight: 0,
        ),
        0.42,
      );
      expect(
        PlayerGestureMath.applyDelta(
          current: 0.42,
          deltaY: double.nan,
          trackHeight: 400,
        ),
        0.42,
      );
    });

    test('亮度读回 -1（跟随系统）时用中间值起手，不跳到极端', () {
      expect(PlayerGestureMath.normalizeBrightness(-1), 0.5);
      expect(PlayerGestureMath.normalizeBrightness(null), 0.5);
      expect(PlayerGestureMath.normalizeBrightness(0.3), 0.3);
      expect(PlayerGestureMath.normalizeBrightness(1.5), 1.0);
    });

    test('百分比文案', () {
      expect(PlayerGestureMath.percentText(0.732), '73%');
      expect(PlayerGestureMath.percentText(1.0), '100%');
      expect(PlayerGestureMath.percentText(-1), '0%');
    });

    test('哪半边管什么：左半屏亮度、右半屏音量（含边界与异常宽度）', () {
      expect(PlayerGestureMath.isBrightnessSide(dx: 10, width: 400), isTrue);
      expect(PlayerGestureMath.isBrightnessSide(dx: 199, width: 400), isTrue);
      expect(PlayerGestureMath.isBrightnessSide(dx: 200, width: 400), isFalse);
      expect(PlayerGestureMath.isBrightnessSide(dx: 390, width: 400), isFalse);
      // 宽度拿不到（0）时兜到亮度，避免手势整个失效。
      expect(PlayerGestureMath.isBrightnessSide(dx: 5, width: 0), isTrue);
    });
  });
}

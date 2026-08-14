import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:box/novel/pages/reader/reader_keyboard_intents.dart';

/// 构造一个按键事件。[isRepeat] 为 true 时构造 KeyRepeatEvent。
KeyEvent _down(LogicalKeyboardKey key, {bool isRepeat = false}) {
  final data = (
    physicalKey: PhysicalKeyboardKey.keyA, // 物理键不参与映射，占位即可
    logicalKey: key,
    timeStamp: Duration.zero,
  );
  return isRepeat
      ? KeyRepeatEvent(
          physicalKey: data.physicalKey,
          logicalKey: data.logicalKey,
          timeStamp: data.timeStamp,
        )
      : KeyDownEvent(
          physicalKey: data.physicalKey,
          logicalKey: data.logicalKey,
          timeStamp: data.timeStamp,
        );
}

KeyEvent _up(LogicalKeyboardKey key) => KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

/// 模拟修饰键按下。HardwareKeyboard.instance 是全局单例，
/// 测试里通过注入真实按键事件来设置 logicalKeysPressed。
Future<void> _holdModifier(LogicalKeyboardKey key) async {
  await simulateKeyDownEvent(key);
}

Future<void> _releaseModifier(LogicalKeyboardKey key) async {
  await simulateKeyUpEvent(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mapReaderKeyIntent 无修饰键', () {
    test('左 / 上 / PageUp 都映射为上一页', () {
      for (final key in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.pageUp,
      ]) {
        expect(
          mapReaderKeyIntent(_down(key)),
          ReaderKeyIntent.previousPage,
          reason: '$key 应为上一页',
        );
      }
    });

    test('右 / 下 / PageDown / 空格 都映射为下一页', () {
      for (final key in [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.space,
      ]) {
        expect(
          mapReaderKeyIntent(_down(key)),
          ReaderKeyIntent.nextPage,
          reason: '$key 应为下一页',
        );
      }
    });

    test('Enter / M 切换菜单', () {
      expect(
        mapReaderKeyIntent(_down(LogicalKeyboardKey.enter)),
        ReaderKeyIntent.toggleMenu,
      );
      expect(
        mapReaderKeyIntent(_down(LogicalKeyboardKey.keyM)),
        ReaderKeyIntent.toggleMenu,
      );
    });

    test('Esc / Backspace 映射为 dismiss', () {
      expect(
        mapReaderKeyIntent(_down(LogicalKeyboardKey.escape)),
        ReaderKeyIntent.dismiss,
      );
      expect(
        mapReaderKeyIntent(_down(LogicalKeyboardKey.backspace)),
        ReaderKeyIntent.dismiss,
      );
    });

    test('未绑定的键返回 null，不吞按键', () {
      expect(mapReaderKeyIntent(_down(LogicalKeyboardKey.keyZ)), isNull);
      expect(mapReaderKeyIntent(_down(LogicalKeyboardKey.tab)), isNull);
      expect(mapReaderKeyIntent(_down(LogicalKeyboardKey.f5)), isNull);
    });
  });

  group('mapReaderKeyIntent 事件类型过滤', () {
    test('KeyUp 一律忽略，否则一次按键会翻两页', () {
      expect(mapReaderKeyIntent(_up(LogicalKeyboardKey.arrowRight)), isNull);
      expect(mapReaderKeyIntent(_up(LogicalKeyboardKey.space)), isNull);
      expect(mapReaderKeyIntent(_up(LogicalKeyboardKey.escape)), isNull);
    });

    test('KeyRepeat 保留，支持按住连续翻页', () {
      expect(
        mapReaderKeyIntent(_down(LogicalKeyboardKey.arrowRight, isRepeat: true)),
        ReaderKeyIntent.nextPage,
      );
      expect(
        mapReaderKeyIntent(_down(LogicalKeyboardKey.arrowLeft, isRepeat: true)),
        ReaderKeyIntent.previousPage,
      );
    });
  });

  group('mapReaderKeyIntent Shift 跨章', () {
    tearDown(() async {
      await _releaseModifier(LogicalKeyboardKey.shiftLeft);
    });

    test('Shift+左右映射为上/下一章，而非翻页', () async {
      await _holdModifier(LogicalKeyboardKey.shiftLeft);

      expect(
        mapReaderKeyIntent(_down(LogicalKeyboardKey.arrowLeft)),
        ReaderKeyIntent.previousChapter,
      );
      expect(
        mapReaderKeyIntent(_down(LogicalKeyboardKey.arrowRight)),
        ReaderKeyIntent.nextChapter,
      );
    });

    test('Shift + 其他键不误命中翻页', () async {
      await _holdModifier(LogicalKeyboardKey.shiftLeft);

      expect(mapReaderKeyIntent(_down(LogicalKeyboardKey.space)), isNull);
      expect(mapReaderKeyIntent(_down(LogicalKeyboardKey.arrowUp)), isNull);
    });
  });

  group('mapReaderKeyIntent Ctrl 字号', () {
    tearDown(() async {
      await _releaseModifier(LogicalKeyboardKey.controlLeft);
    });

    test('Ctrl + 等号/加号 调大字号', () async {
      await _holdModifier(LogicalKeyboardKey.controlLeft);

      for (final key in [
        LogicalKeyboardKey.equal,
        LogicalKeyboardKey.add,
        LogicalKeyboardKey.numpadAdd,
      ]) {
        expect(
          mapReaderKeyIntent(_down(key)),
          ReaderKeyIntent.increaseFontSize,
          reason: 'Ctrl+$key 应调大字号',
        );
      }
    });

    test('Ctrl + 减号 调小字号', () async {
      await _holdModifier(LogicalKeyboardKey.controlLeft);

      for (final key in [
        LogicalKeyboardKey.minus,
        LogicalKeyboardKey.numpadSubtract,
      ]) {
        expect(
          mapReaderKeyIntent(_down(key)),
          ReaderKeyIntent.decreaseFontSize,
          reason: 'Ctrl+$key 应调小字号',
        );
      }
    });

    test('Ctrl+方向键不被当成翻页（留给系统 / 未来快捷键）', () async {
      await _holdModifier(LogicalKeyboardKey.controlLeft);

      expect(mapReaderKeyIntent(_down(LogicalKeyboardKey.arrowLeft)), isNull);
      expect(mapReaderKeyIntent(_down(LogicalKeyboardKey.arrowRight)), isNull);
      expect(mapReaderKeyIntent(_down(LogicalKeyboardKey.space)), isNull);
    });
  });
}

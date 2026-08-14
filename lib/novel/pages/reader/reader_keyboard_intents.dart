import 'package:flutter/services.dart';

/// 阅读页键盘意图。
///
/// 与具体按键解耦，方便后续改键位或加入自定义映射。
enum ReaderKeyIntent {
  /// 上一页 / 上一章（分页模式），或向上滚动一屏（滚动模式）。
  previousPage,

  /// 下一页 / 下一章（分页模式），或向下滚动一屏（滚动模式）。
  nextPage,

  /// 上一章（无论当前处于章内什么位置）。
  previousChapter,

  /// 下一章。
  nextChapter,

  /// 切换菜单显隐。
  toggleMenu,

  /// 关闭菜单 / 退出阅读页（Esc、Backspace）。
  dismiss,

  /// 调大字号。
  increaseFontSize,

  /// 调小字号。
  decreaseFontSize,
}

/// 把物理按键事件翻译成阅读意图。
///
/// 抽成纯函数是为了能在没有 widget 树的情况下穷举键位组合——
/// 键盘映射的分支比翻页逻辑本身多，靠 widget 测试覆盖不划算。
///
/// 只处理 [KeyDownEvent] 与 [KeyRepeatEvent]：
/// KeyUp 会让每次按键触发两次翻页，KeyRepeat 保留是为了支持按住连续翻页。
ReaderKeyIntent? mapReaderKeyIntent(KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;

  final key = event.logicalKey;
  final pressed = HardwareKeyboard.instance.logicalKeysPressed;
  final ctrl = pressed.contains(LogicalKeyboardKey.controlLeft) ||
      pressed.contains(LogicalKeyboardKey.controlRight);
  final shift = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
      pressed.contains(LogicalKeyboardKey.shiftRight);

  // Ctrl + 加/减：字号。放在方向键判断之前，
  // 避免 Ctrl+方向键被误当成翻页。
  if (ctrl) {
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      return ReaderKeyIntent.increaseFontSize;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      return ReaderKeyIntent.decreaseFontSize;
    }
    return null;
  }

  // Shift + 左右：跨章跳转。章跳转是破坏性操作（丢失当前章内位置），
  // 加修饰键防误触。
  if (shift) {
    if (key == LogicalKeyboardKey.arrowLeft) {
      return ReaderKeyIntent.previousChapter;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return ReaderKeyIntent.nextChapter;
    }
    return null;
  }

  // 上一页：左、上、PageUp
  if (key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.pageUp) {
    return ReaderKeyIntent.previousPage;
  }

  // 下一页：右、下、PageDown、空格
  if (key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.pageDown ||
      key == LogicalKeyboardKey.space) {
    return ReaderKeyIntent.nextPage;
  }

  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.keyM) {
    return ReaderKeyIntent.toggleMenu;
  }

  if (key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.backspace) {
    return ReaderKeyIntent.dismiss;
  }

  return null;
}

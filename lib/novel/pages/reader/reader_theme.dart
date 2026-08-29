import 'package:flutter/material.dart';

import '../../core/models.dart';

/// 阅读器配色。
///
/// 三套主题的背景 / 前景色原本是 `_ReaderPageState` 上的两个 getter，
/// 埋在 1372 行的 State 里既无法单测也无法复用。抽成不可变值对象后，
/// 配色变成 `themeMode` 的纯函数：新增主题只要在这里加一个常量，
/// [of] 的 switch 会在编译期提醒补齐分支，而不是静默落到某个默认值。
@immutable
class ReaderPalette {
  const ReaderPalette({required this.background, required this.text});

  /// 米绿护眼
  static const ReaderPalette warm = ReaderPalette(
    background: Color(0xFFDDEBD2),
    text: Color(0xFF161F1A),
  );

  /// 米黄纸张
  static const ReaderPalette paper = ReaderPalette(
    background: Color(0xFFF6EFD8),
    text: Color(0xFF2C2C2C),
  );

  /// 夜间
  static const ReaderPalette dark = ReaderPalette(
    background: Color(0xFF1E2028),
    text: Color(0xFFD0C8B8),
  );

  /// 正文背景色
  final Color background;

  /// 正文前景色。所有次级元素都由它按 alpha 派生，保证同主题内色相一致。
  final Color text;

  /// 按主题取配色。
  ///
  /// 用穷尽 switch 而非 map 查表：enum 新增成员时编译失败，
  /// 比运行时拿到 null 再兜底安全。
  static ReaderPalette of(ReaderThemeMode mode) {
    switch (mode) {
      case ReaderThemeMode.warm:
        return warm;
      case ReaderThemeMode.paper:
        return paper;
      case ReaderThemeMode.dark:
        return dark;
    }
  }
}

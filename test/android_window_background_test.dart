import 'dart:io';

import 'package:box/design_system/app_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

/// 小窗缩放白屏的缓解措施回归测试。
///
/// 现象：红米 K80（HyperOS）小窗里拖拽改变窗口大小 → 整片白屏。
/// 机制：MainActivity 是标准 FlutterActivity，默认 BackgroundMode.opaque
///       → RenderMode.surface → FlutterSurfaceView。SurfaceView 的画面是
///       独立 surface，小窗缩放时要销毁重建；重建后新 surface 还没被填充的
///       那一段，露出的就是 Activity 窗口的 windowBackground。
///
/// 原先 NormalTheme 的 windowBackground = ?android:colorBackground，
/// 在 Theme.Light.NoTitleBar 下正好是纯白 —— 所以「漏出来」看着就是白屏。
/// 深色模式下 values-night 继承 Theme.Black，漏出来是纯黑，同样突兀
/// （这个 App 只有浅色主题，Flutter UI 永远是 #F4F7FB）。
///
/// 这组测试守住：两个 styles.xml 的 windowBackground 都指向和 Flutter
/// 首帧一致的真实背景色，让 surface 重建的空窗期从「刺眼白屏」变成
/// 「和内容同色，几乎看不出」。
///
/// 注意：这是缓解不是根治。根因在引擎的 surface 重建路径里，改不了。
void main() {
  const resDir = 'android/app/src/main/res';

  String readStyles(String flavor) {
    final f = File('$resDir/$flavor/styles.xml');
      expect(
      f.existsSync(),
      isTrue,
      reason: '$flavor/styles.xml 不存在，Android 主题配置被移动或删除了',
    );
    return f.readAsStringSync();
  }

  String readColors() {
    final f = File('$resDir/values/colors.xml');
    expect(
      f.existsSync(),
      isTrue,
      reason: 'values/colors.xml 不存在 —— 窗口底色定义丢了',
    );
    return f.readAsStringSync();
  }

  /// 取 <color name="..."> 的值。
  String? colorValue(String xml, String name) {
    final m = RegExp(
      '<color\\s+name="$name"\\s*>\\s*(#[0-9a-fA-F]{6,8})\\s*</color>',
    ).firstMatch(xml);
    return m?.group(1)?.toUpperCase();
  }

  /// 取指定 style 里 windowBackground 的取值。
  String? windowBackgroundOf(String xml, String styleName) {
    final styleBlock = RegExp(
      '<style\\s+name="$styleName"[^>]*>(.*?)</style>',
      dotAll: true,
    ).firstMatch(xml);
    if (styleBlock == null) return null;
    final m = RegExp(
      r'<item\s+name="android:windowBackground"\s*>\s*([^<]+?)\s*</item>',
    ).firstMatch(styleBlock.group(1)!);
    return m?.group(1)?.trim();
  }

  group('窗口底色与 Flutter 首帧一致（小窗缩放白屏缓解）', () {
    test('colors.xml 里定义了 window_background', () {
      expect(
        colorValue(readColors(), 'window_background'),
        isNotNull,
        reason: 'window_background 颜色没定义，NormalTheme 无从引用',
      );
    });

    test('window_background 等于 AppTokens.background 的真实值', () {
      final declared = colorValue(readColors(), 'window_background');
      // AppTokens.background 是 Flutter 侧 scaffoldBackgroundColor，
      // surface 重建露出的底色必须和它一致才看不出接缝。
      final expected =
          '#${(AppTokens.background.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
      expect(
        declared,
        expected,
        reason: 'Android 窗口底色与 Flutter scaffoldBackgroundColor 不一致，'
            'surface 重建时会看到明显色差',
      );
    });

    test('浅色 NormalTheme 不再用 ?android:colorBackground', () {
      final wb = windowBackgroundOf(readStyles('values'), 'NormalTheme');
      expect(wb, isNotNull, reason: 'NormalTheme 的 windowBackground 被删了');
      expect(
        wb,
        isNot(contains('colorBackground')),
        reason: '?android:colorBackground 在 Theme.Light 下是纯白，'
            '正是小窗缩放白屏看到的那个白',
      );
      expect(wb, '@color/window_background');
    });

    test('深色 NormalTheme 也指向同一个背景色', () {
      // 这个 App 只有浅色主题（没有 darkTheme/ThemeMode），
      // 系统深色模式下若窗口底色是黑，surface 重建会漏出黑屏。
      final wb = windowBackgroundOf(readStyles('values-night'), 'NormalTheme');
      expect(wb, isNotNull, reason: 'values-night 的 NormalTheme 被删了');
      expect(
        wb,
        isNot(contains('colorBackground')),
        reason: 'values-night 继承 Theme.Black，?android:colorBackground 是纯黑',
      );
      expect(wb, '@color/window_background');
    });

    test('启动图底色同样跟随，冷启动不闪白', () {
      final f = File('$resDir/drawable/launch_background.xml');
      expect(f.existsSync(), isTrue);
      final xml = f.readAsStringSync();
      expect(
        xml,
        isNot(contains('@android:color/white')),
        reason: '启动图仍是硬编码纯白，冷启动会闪一下白再跳到 #F4F7FB',
      );
      expect(xml, contains('@color/window_background'));
    });
  });
}

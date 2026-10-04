import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_tokens.dart';

/// 深色外壳的三种档位。
enum AppThemePreference {
  system('跟随系统'),
  light('一直亮'),
  dark('一直暗');

  const AppThemePreference(this.label);

  /// 给设置页显示的中文名。写在这里而不是设置页里，是为了让「档位 → 文案」
  /// 只有一份（设置页、用例、将来的说明文档都读这里）。
  final String label;

  static AppThemePreference fromCode(String? code) {
    for (final value in AppThemePreference.values) {
      if (value.name == code) return value;
    }
    return AppThemePreference.system;
  }
}

/// 深色外壳的全局开关。
///
/// 为什么是一个全局单例 + `AppTokens` 静态色值，而不是 `ThemeExtension`：
/// tokens 被引用 1421 次 / 93 个文件，逐个改成 `AppTokens.of(context).x`
/// 等于重写整个设计系统的调用面；这里只在构建前把「当前是不是深色」写进
/// `AppTokens`，引用点一行不动。**代价**是 `AppTokens` 的表面/文字色不再是
/// 编译期常量，原先写在 `const` 构造里的调用要去掉 `const`。
///
/// 单一真源：档位（用户选的）+ 系统亮度（平台给的）→ 是否深色（唯一的判据）。
/// 设置页、MaterialApp 的 `themeMode`、系统状态栏图标都读这里，不各算一遍。
class AppThemeController extends ChangeNotifier {
  AppThemeController._();

  static final AppThemeController instance = AppThemeController._();

  /// 落盘键。放在 design_system 里而不是设置页，是因为它是外壳的属性。
  static const String storageKey = 'app_theme_mode_v1';

  AppThemePreference _preference = AppThemePreference.system;
  Brightness _platformBrightness = Brightness.light;
  bool _loaded = false;

  AppThemePreference get preference => _preference;

  /// 用户是否已经选过（没选过 = 一直跟随系统）。
  bool get loaded => _loaded;

  /// **唯一的判据**：档位 + 系统亮度。
  bool get isDark =>
      _preference == AppThemePreference.dark ||
      (_preference == AppThemePreference.system &&
          _platformBrightness == Brightness.dark);

  /// 交给 `MaterialApp.themeMode`：`system` 时让 Flutter 自己按系统走，
  /// 但要与 [isDark] 的判据一致（两边不一致会出现「底色深了、对话框还是白的」）。
  ThemeMode get themeMode => switch (_preference) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };

  /// 启动时读一次盘。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _preference = AppThemePreference.fromCode(prefs.getString(storageKey));
    } catch (_) {
      // 读不到就按跟随系统，不把启动流程拖住，也不假报成功。
      _preference = AppThemePreference.system;
    }
    _loaded = true;
    _apply();
  }

  /// 用户改档位：先落盘再重建，失败也不回滚界面（下次启动回到旧值，
  /// 比"点了没反应"更容易解释）。
  Future<void> setPreference(AppThemePreference value) async {
    if (value == _preference) return;
    _preference = value;
    _apply();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, value.name);
    } catch (_) {
      // 忽略：界面已经切过去了，写盘失败不该弹错。
    }
  }

  /// 系统亮度变化（`WidgetsBindingObserver.didChangePlatformBrightness`）。
  void updatePlatformBrightness(Brightness value) {
    if (value == _platformBrightness) return;
    _platformBrightness = value;
    if (_preference == AppThemePreference.system) _apply();
  }

  /// 把当前判据写进 `AppTokens` 并通知重建。
  void _apply() {
    AppTokens.setDark(isDark);
    notifyListeners();
  }

  /// 供用例使用：把控制器恢复到初始态（单例状态会跨用例残留）。
  @visibleForTesting
  void resetForTest({
    AppThemePreference preference = AppThemePreference.system,
    Brightness platformBrightness = Brightness.light,
  }) {
    _preference = preference;
    _platformBrightness = platformBrightness;
    _loaded = false;
    _apply();
  }
}

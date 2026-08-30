import 'package:shared_preferences/shared_preferences.dart';

/// 记录用户「忽略」过的更新版本，让启动弹窗不再重复打扰。
///
/// 设计要点：
/// - 只存**一个** versionCode，语义是「我已看过并跳过到这个版本为止」。
///   服务端一旦发布更高的 versionCode，`shouldShow` 立刻恢复为 true，
///   无需任何清理逻辑，也不会因为历史记录堆积而漏弹。
/// - 强更不受忽略影响，这层判断放在调用方（bootstrap），本类不做例外，
///   避免「忽略」被误用成绕过强更的后门。
/// - 手动检查更新必须无视忽略状态，否则用户点了「检查更新」却没反应，
///   会以为功能坏了。同理由调用方决定是否查询本类。
class UpdateIgnoreStore {
  UpdateIgnoreStore._();

  static final UpdateIgnoreStore instance = UpdateIgnoreStore._();

  static const String _key = 'update_ignored_version_code_v1';

  /// 仅测试注入：避免单测碰真实 SharedPreferences 单例。
  int? _overrideValue;
  bool _useOverride = false;

  /// 仅测试注入：替换底层读取，用来确定性地复现「存储永久挂起」。
  /// 生产路径为 null，走真实 SharedPreferences。
  Future<int?> Function()? _rawReadOverride;

  /// 供测试用：模拟底层读取永久挂起（既不返回也不抛）。
  void debugUseHangingStorage() {
    _useOverride = false;
    _overrideValue = null;
    _rawReadOverride = () => Future<int?>.delayed(
      const Duration(days: 1),
      () => null,
    );
  }

  /// 供测试用：把存储切成内存态。
  void debugUseInMemory({int? initial}) {
    _useOverride = true;
    _overrideValue = initial;
  }

  void debugReset() {
    _useOverride = false;
    _overrideValue = null;
    _rawReadOverride = null;
  }

  /// 读忽略状态的超时上限。
  ///
  /// 为什么必须有：`SharedPreferences.getInstance()` 在缺少 platform channel 的
  /// 环境下**既不返回也不抛异常**（实测 widget 测试里永久挂起），只 catch 异常
  /// 挡不住这种情况。一旦挂住，更新提示就被永久吞掉——比每次都弹严重得多。
  /// 调大：更能读到真实忽略状态，但异常环境下卡更久；调小：更快放行去弹窗，
  /// 代价是慢速设备上偶尔多弹一次（可接受，忽略状态本身不是强约束）。
  static const Duration readTimeout = Duration(seconds: 2);

  Future<int?> readIgnoredVersionCode() async {
    if (_useOverride) return _overrideValue;
    try {
      final raw = _rawReadOverride;
      if (raw != null) return await raw().timeout(readTimeout);
      final prefs = await SharedPreferences.getInstance().timeout(readTimeout);
      return prefs.getInt(_key);
    } catch (_) {
      // 读不到（异常或超时）就当没忽略过：宁可多弹一次，
      // 也不要因为存储不可用把更新提示永久吞掉。
      return null;
    }
  }

  Future<void> ignoreVersion(int versionCode) async {
    if (versionCode <= 0) return;
    if (_useOverride) {
      _overrideValue = versionCode;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance().timeout(readTimeout);
      await prefs.setInt(_key, versionCode).timeout(readTimeout);
    } catch (_) {
      // 写失败（异常或超时）只是下次还会弹，不影响可用性，不打扰用户。
    }
  }

  Future<void> clear() async {
    if (_useOverride) {
      _overrideValue = null;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance().timeout(readTimeout);
      await prefs.remove(_key).timeout(readTimeout);
    } catch (_) {}
  }

  /// 启动时是否应当弹更新提示。
  ///
  /// [force] 为 true 时无条件返回 true：强更不能被忽略。
  Future<bool> shouldShowForVersion(
    int latestVersionCode, {
    bool force = false,
  }) async {
    if (force) return true;
    final ignored = await readIgnoredVersionCode();
    if (ignored == null) return true;
    // 只要线上版本比忽略过的更高，就重新提示。
    return latestVersionCode > ignored;
  }
}

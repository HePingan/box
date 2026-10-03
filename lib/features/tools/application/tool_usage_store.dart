import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一个工具的使用记录。
@immutable
class ToolUsage {
  const ToolUsage({required this.count, required this.lastUsedMs});

  /// 累计打开次数。
  final int count;

  /// 最后一次打开的时间戳（毫秒）。0 表示没有记录。
  final int lastUsedMs;

  Map<String, Object?> toJson() => {'c': count, 't': lastUsedMs};

  /// 宽容解码：字段缺失或类型不对时给一个安全值，不抛。
  static ToolUsage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final c = raw['c'];
    final t = raw['t'];
    if (c is! int || t is! int || c <= 0 || t < 0) return null;
    return ToolUsage(count: c, lastUsedMs: t);
  }
}

/// 工具使用记录（设备本地）。
///
/// 只解决一件事：让工具页顶部那一行「常用」浮出用户真正常用的几个工具。
/// 工具页现在有 66 个可用入口 —— 搜索解决「我知道我要什么」，
/// 这一行解决「我天天用的是那个」。
///
/// **刻意不进备份**：`CustomSiteStore` 那种数据要跟着「本地备份」走，
/// 因为它是用户攒下来的资产；使用计数只是这台设备上的行为痕迹，
/// 恢复到新机上没有意义（还会把旧机器的习惯带过去，让「常用」一开始就是错的）。
/// 所以 `BackupPrefKeys.fixedKeys` 里没有它 —— 这是有意的，不是漏了。
class ToolUsageStore extends ChangeNotifier {
  ToolUsageStore._();

  /// 仅供测试：造一个**单例之外**的独立实例。
  ///
  /// 用来验证「冷启动重新读盘」这条路 —— 单例自己记着 `_loaded`，没法自证刷新。
  @visibleForTesting
  ToolUsageStore.forTest() : super();

  /// 全局单例：工具页与 ApiHub 页读同一份记录，一个地方点过，
  /// 另一个地方的「常用/最近」也跟着动。
  static final ToolUsageStore instance = ToolUsageStore._();

  /// 存储键。
  static const String prefsKey = 'tools_usage_v1';

  /// 记录条数上限。只留用户真正在用的那些，不让无限增长 ——
  /// 66 个工具全点一遍也不会撑爆这个键。
  static const int maxRecords = 40;

  /// 读写钩子。纯 Dart 测试环境没有 shared_preferences 的平台实现，
  /// 替换这两个钩子才能验证持久化链路（沿用 `CustomSiteStore` 的写法）。
  static Future<String?> Function() readRaw = _defaultReadRaw;
  static Future<void> Function(String raw) writeRaw = _defaultWriteRaw;

  static Future<String?> _defaultReadRaw() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefsKey);
  }

  static Future<void> _defaultWriteRaw(String raw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, raw);
  }

  /// 还原钩子，避免替换过的钩子泄漏到后续用例。
  static void resetHooksForTest() {
    readRaw = _defaultReadRaw;
    writeRaw = _defaultWriteRaw;
  }

  final Map<String, ToolUsage> _byName = <String, ToolUsage>{};
  bool _loaded = false;

  /// 是否已经从存储里读过一次。读之前 [recentNames] 返回空 ——
  /// 页面据此区分「还没读」与「真没记录」，不拿 0 冒充。
  bool get loaded => _loaded;

  /// 注入当前毫秒时间（测试可控）。
  @visibleForTesting
  static int Function() nowMs = _defaultNowMs;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  /// 从存储读一次。可重复调用（已读就直接返回）。
  ///
  /// 存储损坏时当作空记录 —— 工具页不该因为一条坏数据打不开。
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    String? raw;
    try {
      raw = await readRaw();
    } catch (_) {
      raw = null;
    }
    _byName.clear();
    final text = raw?.trim() ?? '';
    if (text.isNotEmpty) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (key is! String) return;
            final usage = ToolUsage.fromJson(value);
            if (usage != null) _byName[key] = usage;
          });
        }
      } catch (_) {
        _byName.clear();
      }
    }
    _loaded = true;
    notifyListeners();
  }

  /// 记一次「打开了某个工具」。立刻写盘再通知 —— 调用方（用例、页面）
  /// 读到的必须是已经落地的值，不能是还没写进去的计数。
  Future<void> record(String toolName) async {
    final name = toolName.trim();
    if (name.isEmpty) return;
    if (!_loaded) await ensureLoaded();
    final old = _byName[name];
    _byName[name] = ToolUsage(
      count: (old?.count ?? 0) + 1,
      lastUsedMs: nowMs(),
    );
    _trimToLimit();
    await _persist();
    notifyListeners();
  }

  /// 超过上限时，丢掉「次数最少、且最久没打开」的那些。
  void _trimToLimit() {
    if (_byName.length <= maxRecords) return;
    final entries = _byName.entries.toList()
      ..sort((a, b) {
        final byCount = a.value.count.compareTo(b.value.count);
        if (byCount != 0) return byCount;
        return a.value.lastUsedMs.compareTo(b.value.lastUsedMs);
      });
    for (final e in entries.take(_byName.length - maxRecords)) {
      _byName.remove(e.key);
    }
  }

  /// 常用工具名（按「次数优先、最近其次」排）。次数相同时新的在前。
  ///
  /// 刻意不用带时间衰减的 frecency 公式：这个页面只需要「稳定地把常用的排前面」，
  /// 一个能一眼看懂的排序规则比一个调参公式更好维护，也不会因为长期没用
  /// 就把某个工具悄悄藏起来（那是搜索的活）。
  List<String> recentNames({int limit = 6}) {
    final entries = _byName.entries.where((e) => e.value.count > 0).toList()
      ..sort((a, b) {
        final byCount = b.value.count.compareTo(a.value.count);
        if (byCount != 0) return byCount;
        return b.value.lastUsedMs.compareTo(a.value.lastUsedMs);
      });
    return [for (final e in entries.take(limit)) e.key];
  }

  /// 某个工具用过几次（没记录返回 0）。
  int countOf(String toolName) => _byName[toolName]?.count ?? 0;

  /// 清空全部记录。
  Future<void> clear() async {
    _byName.clear();
    _loaded = true;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final payload = <String, Object?>{
      for (final e in _byName.entries) e.key: e.value.toJson(),
    };
    try {
      await writeRaw(jsonEncode(payload));
    } catch (_) {
      // 写失败不影响本次使用：计数是锦上添花，不能让它把点击卡住。
    }
  }
}

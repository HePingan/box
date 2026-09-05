import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log_channels.dart';

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  /// 兼容旧版本 key，但建议保留当前 key 不动
  static const String _prefsKey = 'video_app_debug_logs_v2';

  /// 最大保留行数
  static const int _maxLines = 1000;

  /// 防抖写入时间
  static const Duration _flushDelay = Duration(milliseconds: 250);

  final ValueNotifier<List<String>> lines = ValueNotifier<List<String>>(
    <String>[],
  );

  SharedPreferences? _prefs;
  bool _inited = false;
  bool _dirty = false;
  Timer? _flushTimer;

  Future<void> init() async {
    if (_inited) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      final stored = _prefs!.getString(_prefsKey);

      lines.value = List<String>.unmodifiable(_decodeStoredLines(stored));
      _inited = true;

      // 把阅读器那套独立日志的历史数据并过来，否则统一入口后
      // 用户升级前记下的阅读日志就再也看不到了。
      await _absorbLegacyReaderLog();

      logTo(LogChannel.system, 'Logger initialized');
    } catch (e, st) {
      // 即便初始化失败，也不要让主流程崩
      debugPrint('[AppLogger] init failed: $e');
      debugPrint('$st');
      _inited = true;
      lines.value = const <String>[];
    }
  }

  String _stamp() {
    return DateTime.now().toIso8601String();
  }

  /// 旧 `ReaderDebugLog` 的 SharedPreferences key。
  ///
  /// 那套系统写的是 `[12:34:56.789] 正文`（无 tag、换行拼接），统一入口后
  /// 它不再被写入，但用户手机上可能还存着报障需要的历史数据，所以启动时
  /// 搬一次并删除原 key，避免每次启动重复导入。
  static const String _legacyReaderKey = 'reader_debug_log';

  /// 把 `[12:34:56.789] 正文` 重排成 `[12:34:56.789][READER][I] 正文`。
  /// 认不出时间片段的行整行当正文，只补标签，不丢内容。
  static String _reshapeLegacyReaderLine(String line) {
    const tag = 'READER';
    const mark = 'I';
    final match = RegExp(
      r'^\[([^\]]*)\]\s?(.*)$',
      dotAll: true,
    ).firstMatch(line);
    if (match == null) {
      return '[][$tag][$mark] $line';
    }
    return '[${match.group(1)}][$tag][$mark] ${match.group(2)}';
  }

  Future<void> _absorbLegacyReaderLog() async {
    final prefs = _prefs;
    if (prefs == null) return;

    final legacy = prefs.getString(_legacyReaderKey);
    if (legacy == null || legacy.trim().isEmpty) return;

    final migrated = legacy
        .split('\n')
        .map((e) => e.trimRight())
        .where((e) => e.trim().isNotEmpty)
        // 旧行形如 `[12:34:56.789] 正文`（只有时分秒，没有日期）。
        // 拆出时间片段重排成标准的 `[时间][READER][I] 正文`，中间不留空格，
        // 否则 LogEntry.parse 认不出第二个方括号是 tag。
        .map(_reshapeLegacyReaderLine)
        .toList(growable: false);

    if (migrated.isEmpty) {
      await prefs.remove(_legacyReaderKey);
      return;
    }

    final merged = <String>[...migrated, ...lines.value];
    if (merged.length > _maxLines) {
      merged.removeRange(0, merged.length - _maxLines);
    }
    lines.value = List<String>.unmodifiable(merged);

    await prefs.remove(_legacyReaderKey);
    _scheduleFlush(merged);
  }

  List<String> _decodeStoredLines(String? stored) {
    if (stored == null || stored.trim().isEmpty) {
      return <String>[];
    }

    // 优先按 JSON 数组解析，兼容多行日志
    try {
      final decoded = jsonDecode(stored);
      if (decoded is List) {
        return decoded
            .map((e) => e?.toString() ?? '')
            .where((e) => e.trim().isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {
      // fallback 到旧格式：按换行分割
    }

    return stored
        .split('\n')
        .map((e) => e.trimRight())
        .where((e) => e.trim().isNotEmpty)
        .toList(growable: false);
  }

  /// 按频道 + 级别记一条日志。新代码用这个，不要再手写裸 tag 字符串。
  ///
  /// 旧的 [log] 保留是为了不动那 40 多处既有调用点（其中 28 处连 tag 都没传），
  /// 两者写出的行都能被 `LogEntry.parse` 认回来。
  void logTo(
    LogChannel channel,
    String message, {
    LogLevel level = LogLevel.info,
  }) {
    _append('[${_stamp()}][${channel.tag}][${level.mark}] $message');
  }

  /// 按频道记录错误，自动落到 error 级别，便于日志页「只看出错的」。
  void logChannelError(
    LogChannel channel,
    Object error, [
    StackTrace? stackTrace,
  ]) {
    logTo(channel, 'Error: $error', level: LogLevel.error);
    if (stackTrace != null) {
      logTo(channel, stackTrace.toString(), level: LogLevel.error);
    }
  }

  void log(String message, {String tag = 'APP'}) {
    _append('[${_stamp()}][$tag] $message');
  }

  void _append(String line) {
    final current = List<String>.from(lines.value)..add(line);
    if (current.length > _maxLines) {
      current.removeRange(0, current.length - _maxLines);
    }

    lines.value = List<String>.unmodifiable(current);

    if (kDebugMode) {
      debugPrint(line);
    }

    _scheduleFlush(current);
  }

  void logBlock(String title, String content, {String tag = 'APP'}) {
    log('════════ $title ════════\n$content\n══════════════════════', tag: tag);
  }

  /// 记录错误。**必须写出级别段**，否则日志页「仅看警告与错误」筛不到。
  ///
  /// 曾经这里转调 [log]，写出两段式 `[时间][TAG] 正文`（无级别段）。
  /// `LogEntry.parse` 对两段式取不到级别，一律落 info —— 于是全部 13 处
  /// 调用点（起播失败、历史写入失败、目录拉取失败…）记下的错误都被当成
  /// 普通信息，用户点「仅看警告与错误」一条都看不到，而这些恰恰是
  /// 「视频打不开」这类报障唯一的现场证据。
  ///
  /// 现在改为走三段式 `[时间][TAG][E] 正文`。tag 仍按调用方传入的字符串
  /// 归位频道，保持 40 多处既有调用点不用改。
  void logError(Object error, [StackTrace? stackTrace, String tag = 'ERROR']) {
    _appendLeveled('Error: $error', tag: tag, level: LogLevel.error);
    if (stackTrace != null) {
      _appendLeveled(stackTrace.toString(), tag: tag, level: LogLevel.error);
    }
  }

  /// 写一条带级别段的日志，tag 保持调用方给的裸字符串。
  ///
  /// 与 [logTo] 的区别：[logTo] 要求调用方已经拿到 [LogChannel] 枚举；
  /// 这里服务于历史调用点传进来的裸 tag（`PLAYER` / `VIDEO_CONTROLLER` …），
  /// 由 `LogChannel.fromTag` 在读取侧归位。
  void _appendLeveled(
    String message, {
    required String tag,
    required LogLevel level,
  }) {
    _append('[${_stamp()}][$tag][${level.mark}] $message');
  }

  void _scheduleFlush(List<String> current) {
    _dirty = true;
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushDelay, () {
      _flushTimer = null;
      unawaited(_flush(current));
    });
  }

  Future<void> _flush(List<String> current) async {
    if (!_dirty) return;
    _dirty = false;

    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;

      // 用 JSON 存储，避免多行日志被拆坏
      await prefs.setString(_prefsKey, jsonEncode(current));
    } catch (_) {
      // 忽略保存失败，避免影响主流程
    }
  }

  /// 主动刷新一次，必要时可在退出前调用
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flush(List<String>.from(lines.value));
  }

  Future<String> exportText() async {
    return lines.value.join('\n');
  }

  Future<void> clear() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _dirty = false;

    lines.value = <String>[];

    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      await prefs.remove(_prefsKey);
    } catch (_) {
      // ignore
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  /// 仅供测试：清掉单例状态后重新走一遍 [init]。
  ///
  /// [init] 有 `_inited` 守卫（生产环境正确——重复初始化会重复导入旧日志），
  /// 但测试需要针对不同的 SharedPreferences 初值反复验证迁移逻辑。
  @visibleForTesting
  Future<void> reinitForTest() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _dirty = false;
    _inited = false;
    _prefs = null;
    lines.value = const <String>[];
    await init();
  }
}

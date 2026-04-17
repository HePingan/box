import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  /// 兼容旧版本 key，但建议保留当前 key 不动
  static const String _prefsKey = 'video_app_debug_logs_v2';

  /// 最大保留行数
  static const int _maxLines = 1000;

  /// 防抖写入时间
  static const Duration _flushDelay = Duration(milliseconds: 250);

  final ValueNotifier<List<String>> lines =
      ValueNotifier<List<String>>(<String>[]);

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

      log('Logger initialized', tag: 'SYSTEM');
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

  void log(String message, {String tag = 'APP'}) {
    final line = '[${_stamp()}][$tag] $message';

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
    log(
      '════════ $title ════════\n$content\n══════════════════════',
      tag: tag,
    );
  }

  void logError(Object error, [StackTrace? stackTrace, String tag = 'ERROR']) {
    log('Error: $error', tag: tag);
    if (stackTrace != null) {
      log(stackTrace.toString(), tag: tag);
    }
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
}
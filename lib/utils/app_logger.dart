import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  static const String _prefsKey = 'video_app_debug_logs_v1';
  static const int _maxLines = 1000;

  final ValueNotifier<List<String>> lines =
      ValueNotifier<List<String>>(<String>[]);

  SharedPreferences? _prefs;
  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;

    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs!.getString(_prefsKey) ?? '';

    if (stored.trim().isEmpty) {
      lines.value = <String>[];
    } else {
      final parsed = stored.split('\n');
      lines.value = List<String>.unmodifiable(parsed);
    }

    _inited = true;
    log('Logger initialized', tag: 'SYSTEM');
  }

  String _stamp() {
    final now = DateTime.now();
    return now.toIso8601String();
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

    _save(current);
  }

  void logBlock(String title, String content, {String tag = 'APP'}) {
    log('════════ $title ════════\n$content\n══════════════════════', tag: tag);
  }

  void logError(Object error, [StackTrace? stackTrace, String tag = 'ERROR']) {
    log('Error: $error', tag: tag);
    if (stackTrace != null) {
      log(stackTrace.toString(), tag: tag);
    }
  }

  Future<void> _save(List<String> current) async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      await prefs.setString(_prefsKey, current.join('\n'));
    } catch (_) {
      // 忽略保存失败，避免影响主流程
    }
  }

  Future<String> exportText() async {
    return lines.value.join('\n');
  }

  Future<void> clear() async {
    lines.value = <String>[];
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }
}
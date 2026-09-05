import '../../../utils/app_logger.dart';
import '../../../utils/log_channels.dart';

/// 阅读器调试日志。
///
/// 改造前这是一套**独立**的日志系统：自己的 SharedPreferences key
/// (`reader_debug_log`)、自己的 200 行上限、自己的换行拼接存储，还在阅读界面
/// 上常驻一个橙色虫子 FloatingActionButton。两个问题：
///
/// 1. 那个按钮没有任何 kDebugMode 判断，Release 包里也照样浮在正文上方，
///    每个普通读者都看得见、点得开。
/// 2. 用户报障时只会截其中一套日志，另一套的线索直接丢失。
///
/// 现在它退化成 [AppLogger] 的转发壳：19 处既有调用点一行不用改，日志统一
/// 流进抽屉「更多 → 调试日志」，在那里按「阅读」频道筛选即可。历史数据由
/// `AppLogger.init()` 启动时一次性迁移。
class ReaderDebugLog {
  const ReaderDebugLog._();

  /// 保留空实现：调用点还在 `reader_page.dart` 的 initState 里，
  /// 真正的初始化由 `AppLogger.init()` 在应用启动时统一完成。
  static Future<void> init() async {}

  static void log(String message) {
    AppLogger.instance.logTo(LogChannel.reader, message);
  }

  static Future<void> clear() => AppLogger.instance.clear();

  /// 只返回阅读频道的行，保持原语义（原本这里只存阅读器自己的日志）。
  static List<String> getLogs() {
    return AppLogger.instance.lines.value
        .where((line) => LogEntry.parse(line).channel == LogChannel.reader)
        .toList(growable: false);
  }
}

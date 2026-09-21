import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归：远程存储插件的日志必须落进「存储」频道。
///
/// 背景：远程存储插件此前用 13 处**裸 debugPrint**输出排障日志——
/// debugPrint 只进控制台，不进统一日志缓冲；但用户可见的错误提示里
/// 写着「连接超时，网络不可达（已记入调试日志）」，用户按提示去
/// 「更多 → 调试日志」里翻，按「存储」筛选只会看到空列表。
///
/// 归位到 AppLogger + STORAGE 频道后，这条承诺才真实成立。
/// 与「窗口」频道的教训同构（见 log_channel_window_tag_test.dart）：
/// 枚举里定义了频道、筛选器里露出了选项，就必须有真实写入来源。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLogger.instance.lines.value = const <String>[];
  });

  group('远程存储 tag 归入存储频道', () {
    test('STORAGE → storage', () {
      expect(
        LogChannel.fromTag('STORAGE'),
        LogChannel.storage,
        reason: '存储频道写出的日志必须能被筛选器认回来',
      );
    });

    test('大小写与空格不敏感', () {
      expect(LogChannel.fromTag('  storage '), LogChannel.storage);
      expect(LogChannel.fromTag('Storage'), LogChannel.storage);
    });

    test('写入后能按存储频道筛选到（不是空壳选项）', () {
      AppLogger.instance.logTo(
        LogChannel.storage,
        '远程存储：连接超时，网络不可达',
        level: LogLevel.warn,
      );

      final entries =
          AppLogger.instance.lines.value.map(LogEntry.parse).toList();

      expect(entries, hasLength(1));
      expect(entries.single.channel, LogChannel.storage);
      expect(entries.single.level, LogLevel.warn);
      expect(entries.single.message, contains('连接超时'));
    });

    test('logChannelError 落存储频道且为 error 级别（「已记入调试日志」的场景）', () {
      AppLogger.instance.logChannelError(LogChannel.storage, 'timeout');

      final entries =
          AppLogger.instance.lines.value.map(LogEntry.parse).toList();

      expect(entries, hasLength(1));
      expect(entries.single.channel, LogChannel.storage);
      expect(entries.single.level, LogLevel.error);
      expect(entries.single.message, contains('timeout'));
    });
  });
}

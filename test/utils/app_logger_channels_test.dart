import 'dart:convert';

import 'package:box/novel/pages/reader/reader_debug_log.dart';
import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const logKey = 'video_app_debug_logs_v2';
  const legacyReaderKey = 'reader_debug_log';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLogger.instance.lines.value = const <String>[];
  });

  group('logTo 写出可解析的分频道日志', () {
    test('频道与级别都能被 LogEntry 认回来', () {
      AppLogger.instance.logTo(LogChannel.player, '起播成功');
      AppLogger.instance.logTo(
        LogChannel.reader,
        '分页失败',
        level: LogLevel.error,
      );

      final entries = AppLogger.instance.lines.value
          .map(LogEntry.parse)
          .toList();

      expect(entries, hasLength(2));
      expect(entries[0].channel, LogChannel.player);
      expect(entries[0].level, LogLevel.info);
      expect(entries[0].message, '起播成功');
      expect(entries[1].channel, LogChannel.reader);
      expect(entries[1].level, LogLevel.error);
    });

    test('logChannelError 落在 error 级别，带栈时写两行', () {
      AppLogger.instance.logChannelError(
        LogChannel.network,
        'timeout',
        StackTrace.fromString('#0 fake'),
      );

      final entries = AppLogger.instance.lines.value
          .map(LogEntry.parse)
          .toList();

      expect(entries, hasLength(2));
      expect(entries.every((e) => e.channel == LogChannel.network), isTrue);
      expect(entries.every((e) => e.level == LogLevel.error), isTrue);
      expect(entries.first.message, contains('timeout'));
    });

    test('旧的 log(tag:) 仍然可用且可解析，不破坏既有 40 多处调用点', () {
      AppLogger.instance.log('老式调用', tag: 'VISIBILITY');

      final entry = LogEntry.parse(AppLogger.instance.lines.value.single);

      expect(entry.channel, LogChannel.video);
      expect(entry.message, '老式调用');
    });
  });

  group('阅读器旧日志迁移', () {
    test('启动时把 reader_debug_log 搬进统一日志并打上阅读频道', () async {
      SharedPreferences.setMockInitialValues({
        legacyReaderKey:
            '[10:00:00.100] _saveProgress: START\n'
            '[10:00:00.200] _saveProgress: DONE',
      });

      await AppLogger.instance.reinitForTest();

      final readerLines = AppLogger.instance.lines.value
          .map(LogEntry.parse)
          .where((e) => e.channel == LogChannel.reader)
          .toList();

      expect(readerLines, hasLength(2));
      expect(readerLines[0].message, '_saveProgress: START');
      expect(readerLines[1].message, '_saveProgress: DONE');
    });

    test('迁移后删除旧 key，避免每次启动重复导入', () async {
      SharedPreferences.setMockInitialValues({
        legacyReaderKey: '[10:00:00.100] once',
      });

      await AppLogger.instance.reinitForTest();
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getString(legacyReaderKey), isNull);
    });

    test('旧 key 为空或不存在时不产生垃圾行', () async {
      SharedPreferences.setMockInitialValues({legacyReaderKey: '   '});

      await AppLogger.instance.reinitForTest();

      final readerLines = AppLogger.instance.lines.value
          .map(LogEntry.parse)
          .where((e) => e.channel == LogChannel.reader);

      expect(readerLines, isEmpty);
    });

    test('迁移的行排在已有日志之前，保持时间先后', () async {
      SharedPreferences.setMockInitialValues({
        logKey: jsonEncode(['[2026-09-05T10:00:00.000][PLAYER][I] 后来的事']),
        legacyReaderKey: '[09:00:00.000] 早先的事',
      });

      await AppLogger.instance.reinitForTest();

      final entries = AppLogger.instance.lines.value
          .map(LogEntry.parse)
          .toList();

      expect(entries.first.channel, LogChannel.reader);
      expect(entries.first.message, '早先的事');
      // init() 末尾自己会补一条 SYSTEM "Logger initialized"，
      // 所以已有的 PLAYER 行在倒数第二位，而不是最后一位。
      final playerIndex = entries.indexWhere(
        (e) => e.channel == LogChannel.player,
      );
      final readerIndex = entries.indexWhere(
        (e) => e.channel == LogChannel.reader,
      );
      expect(playerIndex, greaterThan(readerIndex));
      expect(entries[playerIndex].message, '后来的事');
    });

    test('认不出时间片段的旧行也不丢内容', () async {
      SharedPreferences.setMockInitialValues({legacyReaderKey: '没有方括号的裸行'});

      await AppLogger.instance.reinitForTest();

      final readerLines = AppLogger.instance.lines.value
          .map(LogEntry.parse)
          .where((e) => e.channel == LogChannel.reader)
          .toList();

      expect(readerLines, hasLength(1));
      expect(readerLines.single.message, contains('没有方括号的裸行'));
    });
  });

  group('ReaderDebugLog 退化为转发壳', () {
    test('log 转发到统一日志的阅读频道', () {
      ReaderDebugLog.log('翻页了');

      final entry = LogEntry.parse(AppLogger.instance.lines.value.single);

      expect(entry.channel, LogChannel.reader);
      expect(entry.message, '翻页了');
    });

    test('getLogs 只返回阅读频道，不串入播放日志', () {
      AppLogger.instance.logTo(LogChannel.player, '播放日志');
      ReaderDebugLog.log('阅读日志');
      AppLogger.instance.logTo(LogChannel.video, '影视日志');

      final logs = ReaderDebugLog.getLogs();

      expect(logs, hasLength(1));
      expect(logs.single, contains('阅读日志'));
    });

    test('init 是空实现，可安全重复调用', () async {
      await ReaderDebugLog.init();
      await ReaderDebugLog.init();
      // 不应抛异常，也不应写入日志行。
      expect(AppLogger.instance.lines.value, isEmpty);
    });
  });
}

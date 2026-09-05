import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';

/// 回归：`logError` 写出的行必须是 error 级别，且频道归位。
///
/// 背景：`logError(e, st, 'PLAYER')` 内部转调 `log(msg, tag:)`，写出的是
/// 两段式 `[时间][TAG] 正文` —— **没有级别段**。`LogEntry.parse` 对两段式
/// 取 `group(3) == null`，`LogLevel.fromMark(null)` 落到 info。
///
/// 后果：全部 13 处 `logError` 调用点（播放器起播失败、历史写入失败、
/// 影视目录拉取失败、详情填充失败…）记下来的**错误全被当成普通信息**，
/// 用户点「仅看警告与错误」一条都筛不到。而这些恰恰是「视频打不开」这类
/// 报障最需要的现场。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<List<LogEntry>> capture(void Function() act) async {
    await AppLogger.instance.reinitForTest();
    act();
    return AppLogger.instance.lines.value
        .map((e) => LogEntry.parse(e))
        .toList(growable: false);
  }

  group('logError 级别与频道', () {
    test('logError 写出 error 级别，而不是 info', () async {
      final entries = await capture(
        () => AppLogger.instance.logError(StateError('起播失败'), null, 'PLAYER'),
      );

      final errorLines = entries.where((e) => e.message.contains('起播失败'));
      expect(errorLines, hasLength(1));
      expect(
        errorLines.single.level,
        LogLevel.error,
        reason: '「仅看警告与错误」依赖级别段，info 会被直接筛掉',
      );
      expect(
        errorLines.single.channel,
        LogChannel.player,
        reason: 'PLAYER tag 应归入播放频道',
      );
    });

    test('堆栈行同样是 error 级别', () async {
      final entries = await capture(
        () => AppLogger.instance.logError(
          StateError('boom'),
          StackTrace.fromString('#0  foo\n#1  bar'),
          'PLAYER',
        ),
      );

      final stackLines = entries.where((e) => e.message.contains('#0'));
      expect(stackLines, hasLength(1));
      expect(stackLines.single.level, LogLevel.error);
    });

    test('VIDEO_CONTROLLER 归入影视频道', () async {
      // video_controller.dart 有 5 处 logError 用这个 tag，此前未登记，
      // 全部落进 system 兜底，报「影视打不开」时筛「影视」看不到。
      expect(LogChannel.fromTag('VIDEO_CONTROLLER'), LogChannel.video);
    });

    test('默认 tag ERROR 归入错误频道且是 error 级别', () async {
      final entries = await capture(
        () => AppLogger.instance.logError(StateError('x')),
      );
      final line = entries.firstWhere((e) => e.message.contains('Error:'));
      expect(line.channel, LogChannel.error);
      expect(line.level, LogLevel.error);
    });

    test('普通 log 仍是 info，不被误升级', () async {
      final entries = await capture(
        () => AppLogger.instance.log('普通事件', tag: 'PLAYER'),
      );
      final line = entries.firstWhere((e) => e.message.contains('普通事件'));
      expect(line.level, LogLevel.info);
    });
  });

  group('筛选一致性', () {
    test('「仅看警告与错误」能筛到 logError 记下的现场', () async {
      await AppLogger.instance.reinitForTest();
      AppLogger.instance.log('普通信息', tag: 'PLAYER');
      AppLogger.instance.logError(StateError('播放失败'), null, 'PLAYER');

      final entries = AppLogger.instance.lines.value
          .map((e) => LogEntry.parse(e))
          .toList(growable: false);

      // 复刻 debug_log_page 的 _errorsOnly 判据
      final kept = entries.where(
        (e) =>
            e.level == LogLevel.error ||
            e.level == LogLevel.warn ||
            e.channel == LogChannel.error,
      );

      expect(
        kept.where((e) => e.message.contains('播放失败')),
        hasLength(1),
        reason: '报「视频打不开」时这条是唯一的现场证据',
      );
      expect(kept.where((e) => e.message.contains('普通信息')), isEmpty);
    });
  });
}

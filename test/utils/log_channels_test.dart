import 'package:box/utils/log_channels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogChannel.fromTag 历史 tag 归位', () {
    test('影视相关的一堆散装 tag 都收进 video', () {
      for (final raw in [
        'VISIBILITY',
        'COVER',
        'CATALOG',
        'VIDEO_CATALOG',
        'VIDEO_API',
        'DETAIL_FILL',
        'DETAIL_CTRL',
        'HISTORY',
      ]) {
        expect(
          LogChannel.fromTag(raw),
          LogChannel.video,
          reason: '$raw 应归入影视频道',
        );
      }
    });

    test('PLAYER 单独成频道，不被 video 吞掉', () {
      // 用户报「视频卡住」时只想看播放器那几行，混进目录拉取会淹掉线索。
      expect(LogChannel.fromTag('PLAYER'), LogChannel.player);
    });

    test('FLUTTER 与 WINDOW 都归窗口频道（分屏排障靠它）', () {
      expect(LogChannel.fromTag('FLUTTER'), LogChannel.window);
      expect(LogChannel.fromTag('WINDOW'), LogChannel.window);
    });

    test('APP 与 SYSTEM 归系统频道', () {
      expect(LogChannel.fromTag('APP'), LogChannel.system);
      expect(LogChannel.fromTag('SYSTEM'), LogChannel.system);
    });

    test('大小写与空白不影响归类', () {
      expect(LogChannel.fromTag('  player '), LogChannel.player);
      expect(LogChannel.fromTag('Reader'), LogChannel.reader);
    });

    test('null 与未知 tag 兜底到 system，不抛异常也不丢行', () {
      expect(LogChannel.fromTag(null), LogChannel.system);
      // 'latest' 是历史上把参数值误当 tag 传进来的产物，
      // 不该为它新建分类，也不该丢掉这条日志。
      expect(LogChannel.fromTag('latest'), LogChannel.system);
      expect(LogChannel.fromTag(''), LogChannel.system);
      expect(LogChannel.fromTag('随便什么'), LogChannel.system);
    });

    test('每个频道都有非空 tag 和中文标签，且 tag 互不重复', () {
      final tags = <String>{};
      for (final c in LogChannel.values) {
        expect(c.tag.trim(), isNotEmpty);
        expect(c.label.trim(), isNotEmpty);
        expect(c.tag, c.tag.toUpperCase(), reason: 'tag 统一大写便于 grep');
        expect(tags.add(c.tag), isTrue, reason: '${c.tag} 重复');
      }
    });

    test('所有枚举自身的 tag 都能被 fromTag 认回来', () {
      for (final c in LogChannel.values) {
        expect(LogChannel.fromTag(c.tag), c, reason: '${c.tag} 无法回环，筛选器会失效');
      }
    });
  });

  group('LogLevel', () {
    test('单字母标记解析', () {
      expect(LogLevel.fromMark('D'), LogLevel.debug);
      expect(LogLevel.fromMark('I'), LogLevel.info);
      expect(LogLevel.fromMark('W'), LogLevel.warn);
      expect(LogLevel.fromMark('E'), LogLevel.error);
    });

    test('缺失或无法识别时默认 info', () {
      expect(LogLevel.fromMark(null), LogLevel.info);
      expect(LogLevel.fromMark(''), LogLevel.info);
      expect(LogLevel.fromMark('X'), LogLevel.info);
    });
  });

  group('LogEntry.parse 兼容三种历史格式', () {
    test('新格式：时间戳 + tag + 级别', () {
      final entry = LogEntry.parse(
        '[2026-09-05T10:00:00.000][PLAYER][W] 起播超时 retry=2',
      );

      expect(entry.channel, LogChannel.player);
      expect(entry.level, LogLevel.warn);
      expect(entry.message, '起播超时 retry=2');
      expect(entry.timestamp, isNotNull);
      expect(entry.timestamp!.year, 2026);
    });

    test('AppLogger 旧格式：只有时间戳 + tag，级别落 info', () {
      final entry = LogEntry.parse(
        '[2026-09-05T10:00:00.000][VISIBILITY] 卡片进入可视区',
      );

      expect(entry.channel, LogChannel.video);
      expect(entry.level, LogLevel.info);
      expect(entry.message, '卡片进入可视区');
    });

    test('ReaderDebugLog 旧格式：只有一个方括号，靠 fallback 归入阅读', () {
      final entry = LogEntry.parse(
        '[10:00:00.123] _saveProgress: SAVING page=3.00',
        fallbackChannel: LogChannel.reader,
      );

      expect(entry.channel, LogChannel.reader);
      expect(entry.message, '_saveProgress: SAVING page=3.00');
    });

    test('完全不合格式的行整行保留，不被吞掉', () {
      final entry = LogEntry.parse('赤裸裸的一行日志');

      expect(entry.channel, LogChannel.system);
      expect(entry.message, '赤裸裸的一行日志');
      expect(entry.raw, '赤裸裸的一行日志');
    });

    test('多行日志（logBlock 产物）不被截断', () {
      final entry = LogEntry.parse(
        '[2026-09-05T10:00:00.000][QUIZ][I] 第一行\n第二行\n第三行',
      );

      expect(entry.channel, LogChannel.quiz);
      expect(entry.message, contains('第二行'));
      expect(entry.message, contains('第三行'));
    });

    test('raw 始终等于传入原文，便于「复制全部」还原', () {
      const line = '[2026-09-05T10:00:00.000][READER][E] 出错了';
      expect(LogEntry.parse(line).raw, line);
    });

    test('未识别的 tag 也不丢行', () {
      final entry = LogEntry.parse('[2026-09-05T10:00:00.000][latest] 某事发生');

      expect(entry.channel, LogChannel.system);
      expect(entry.message, '某事发生');
    });
  });
}

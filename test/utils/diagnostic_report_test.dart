import 'package:box/utils/diagnostic_report.dart';
import 'package:box/utils/log_channels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final header = DiagnosticHeader(
    appVersion: '1.10.0',
    buildNumber: '201',
    packageName: 'top.hpa888.box',
    osVersion: 'Android 15',
    generatedAt: DateTime.parse('2026-09-05T10:00:00.000'),
  );

  List<LogEntry> entriesOf(List<String> raw) =>
      raw.map(LogEntry.parse).toList(growable: false);

  group('报告头部带齐排障必需的上下文', () {
    test('版本、包名、系统、时间四项都在', () {
      final text = DiagnosticReport.compose(
        header: header,
        entries: const [],
        scopeLabel: '全部',
      );

      expect(text, contains('1.10.0'));
      expect(text, contains('201'));
      expect(text, contains('top.hpa888.box'));
      expect(text, contains('Android 15'));
      expect(text, contains('2026-09-05T10:00:00.000'));
    });

    test('写明日志范围与行数，接收方不必猜是不是全量', () {
      final text = DiagnosticReport.compose(
        header: header,
        entries: entriesOf(['[2026-09-05T10:00:00.000][READER][I] 一行']),
        scopeLabel: '阅读',
      );

      expect(text, contains('日志范围: 阅读'));
      expect(text, contains('日志行数: 1'));
    });

    test('空日志时明确写出来，而不是给一份看不懂的空报告', () {
      final text = DiagnosticReport.compose(
        header: header,
        entries: const [],
        scopeLabel: '全部',
      );

      expect(text, contains('(当前筛选下没有日志)'));
      expect(text, contains('日志行数: 0'));
    });
  });

  group('分类统计', () {
    test('按频道计数，只列出真有日志的分类', () {
      final entries = entriesOf([
        '[2026-09-05T10:00:00.000][PLAYER][I] a',
        '[2026-09-05T10:00:01.000][PLAYER][E] b',
        '[2026-09-05T10:00:02.000][READER][I] c',
      ]);

      final counts = DiagnosticReport.channelCounts(entries);

      expect(counts[LogChannel.player], 2);
      expect(counts[LogChannel.reader], 1);
      expect(counts.containsKey(LogChannel.quiz), isFalse);
    });

    test('统计行出现在报告头部', () {
      final text = DiagnosticReport.compose(
        header: header,
        entries: entriesOf([
          '[2026-09-05T10:00:00.000][PLAYER][I] a',
          '[2026-09-05T10:00:01.000][READER][I] b',
        ]),
        scopeLabel: '全部',
      );

      expect(text, contains('分类统计:'));
      expect(text, contains('播放1'));
      expect(text, contains('阅读1'));
    });

    test('空列表不产生空的统计行', () {
      final text = DiagnosticReport.compose(
        header: header,
        entries: const [],
        scopeLabel: '全部',
      );

      expect(text, isNot(contains('分类统计:')));
    });

    test('统计顺序跟随频道枚举定义，输出稳定可比对', () {
      final entries = entriesOf([
        '[2026-09-05T10:00:00.000][READER][I] r',
        '[2026-09-05T10:00:01.000][SYSTEM][I] s',
        '[2026-09-05T10:00:02.000][PLAYER][I] p',
      ]);

      final keys = DiagnosticReport.channelCounts(entries).keys.toList();

      // 枚举顺序是 system → window → player → video → reader …
      expect(
        keys.indexOf(LogChannel.system),
        lessThan(keys.indexOf(LogChannel.player)),
      );
      expect(
        keys.indexOf(LogChannel.player),
        lessThan(keys.indexOf(LogChannel.reader)),
      );
    });
  });

  group('日志正文', () {
    test('原文逐行保留，便于直接 grep', () {
      const raw = '[2026-09-05T10:00:00.000][PLAYER][E] 起播失败 code=-1';
      final text = DiagnosticReport.compose(
        header: header,
        entries: entriesOf([raw]),
        scopeLabel: '播放',
      );

      expect(text, contains(raw));
    });

    test('多行日志不被压平', () {
      final text = DiagnosticReport.compose(
        header: header,
        entries: entriesOf(['[2026-09-05T10:00:00.000][QUIZ][I] 第一行\n第二行']),
        scopeLabel: '题库',
      );

      expect(text, contains('第一行'));
      expect(text, contains('第二行'));
    });

    test('头部与正文之间有分隔标记，粘贴到聊天里仍可读', () {
      final text = DiagnosticReport.compose(
        header: header,
        entries: entriesOf(['[2026-09-05T10:00:00.000][SYSTEM][I] x']),
        scopeLabel: '全部',
      );

      expect(text, contains('===== Box 诊断报告 ====='));
      expect(text, contains('===== 日志正文 ====='));
    });
  });

  group('DiagnosticHeader.collect 容错', () {
    test('拿不到 package_info 时各字段落到「未知」而不抛异常', () async {
      // 测试环境没有 platform channel，PackageInfo 会失败——
      // 这正是要验的路径：报障流程不能因为取不到版本号就断掉。
      final collected = await DiagnosticHeader.collect();

      expect(collected.appVersion, isNotEmpty);
      expect(collected.packageName, isNotEmpty);
      expect(collected.toLines(), hasLength(4));
    });
  });
}

import 'package:box/utils/app_logger.dart';
import 'package:box/utils/log_channels.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLogger.instance.lines.value = const <String>[];
  });

  /// 报障人的真实处境：他在 App 内的「调试日志」页找题库同步证据。
  /// 这些证据必须**落进 AppLogger**（进 SharedPreferences、能被日志页搜到），
  /// 而不是只走 debugPrint（release 包里不持久化，日志页永远看不到）。
  List<String> quizLines() => AppLogger.instance.lines.value
      .where((l) => LogEntry.parse(l).channel == LogChannel.quiz)
      .toList(growable: false);

  test('题库频道日志能落进 AppLogger，被日志页搜到', () {
    AppLogger.instance.logTo(
      LogChannel.quiz,
      'sync page cursor=4900 hasMore=false',
    );

    final lines = quizLines();
    expect(lines, isNotEmpty, reason: '题库诊断必须进 AppLogger，否则日志页搜不到');

    final parsed = LogEntry.parse(lines.last);
    expect(parsed.channel, LogChannel.quiz);
    expect(parsed.raw, contains('cursor=4900'));
  });

  test('题库错误日志带级别段，能被「仅错误」筛到', () {
    AppLogger.instance.logChannelError(
      LogChannel.quiz,
      'no candidate: bankSize=0',
    );

    final parsed = LogEntry.parse(quizLines().first);
    expect(parsed.level, LogLevel.error);
    expect(parsed.channel, LogChannel.quiz);
  });

  test('搜索能命中题库日志里的题目 ID 片段', () {
    AppLogger.instance.logTo(
      LogChannel.quiz,
      'no candidate q_7gZgweMXMRQd bankSize=0',
    );

    final hit = AppLogger.instance.lines.value
        .where((l) => l.toLowerCase().contains('q_7gzgwemxmrqd'))
        .toList();
    expect(hit, hasLength(1));
  });

  /// 真机 17:02 截图：判断题报「请人工确认」。用户搜不到任何分数证据，
  /// 无法判断是题干分低还是选项分掉下 90。低置信候选必须落分数明细。
  test('低置信候选落分数明细，可搜 score / oScore 调参', () {
    AppLogger.instance.logTo(
      LogChannel.quiz,
      'lowConfidence candidate q=50 o=89 w=0.90 base=66 final=68 qid=q_7gZgweMXMRQd',
    );

    final raw = quizLines().last;
    expect(raw, contains('lowConfidence'));
    expect(raw, contains('q=50'));
    expect(raw, contains('o=89'));
    expect(raw, contains('final=68'));
    expect(LogEntry.parse(raw).channel, LogChannel.quiz);
  });
}

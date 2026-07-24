import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';

void main() {
  test('悬浮窗相似度从结构化 confidence 读取而非正文标记', () {
    const answer = QuizAnswer(
      text: '匹配题目：路口通行\n答案：减速观察',
      confidence: 0.92,
      correctAnswer: '减速观察',
    );

    expect(QuizPluginEntry.similarityPercentForAnswer(answer), 92);
  });
}

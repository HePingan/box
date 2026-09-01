import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';

void main() {
  test('歧义题图候选绝不以答案前缀展示首项', () {
    const result = QuizResult(
      question: '这个标志是何含义？',
      answers: [
        QuizAnswer(
          text: '答案：十字交叉路口',
          correctAnswer: '十字交叉路口',
          confidence: 0.70,
          imageMatchHint: '题图匹配不足：请确认框选的是完整题图\n候选答案：十字交叉路口 / T形交叉路口',
        ),
        QuizAnswer(
          text: '答案：T形交叉路口',
          correctAnswer: 'T形交叉路口',
          confidence: 0.65,
        ),
      ],
    );

    final text = QuizPluginEntry.ambiguousCandidatesForOverlay(result);

    expect(text, '请人工确认\n候选 1：十字交叉路口\n候选 2：T形交叉路口');
    expect(text, isNot(contains('答案：')));
    expect(text, isNot(contains('题图匹配不足')));
  });
}

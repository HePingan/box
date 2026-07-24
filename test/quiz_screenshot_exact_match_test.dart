import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:box/features/quiz_plugin/data/quiz_engine.dart';

void main() {
  const stem = '对未取得驾驶证驾驶机动车的，追究其法律责任。';
  test('截图中的完全相同判断题必须命中本地题库', () async {
    QuizBankCache.instance.assign([
      const QuizBankItem(
        id: 'screenshot-exact',
        question: stem,
        type: QuizQuestionType.trueFalse,
        options: ['正确', '错误'],
        correctAnswer: '正确',
      ),
    ]);
    final normalized = QuizBankTextNormalizer.cleanForMatch(stem);
    expect(QuizBankCache.instance.candidatesFor(normalized), isNotEmpty);

    final result = await QuizEngine(
      config: const QuizConfig(bankEnabled: true),
    ).search(stem, probeOptions: const ['正确', '错误']);
    expect(result.isSuccess, isTrue);
    expect(result.answers.first.correctAnswer, '正确');
    expect(result.answers.first.confidence, 1);
  });
}

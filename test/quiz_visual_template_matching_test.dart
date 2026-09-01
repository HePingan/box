import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  QuizEngine engine() => QuizEngine(
    config: const QuizConfig(
      enabled: true,
      bankEnabled: true,
      autoSearch: false,
      allowExternalApi: false,
      bankMaxMatches: 1,
    ),
  );

  const question = '这个标志是何含义？';
  const options = ['T形交叉路口', 'Y形交叉路口', '十字交叉路口', '环形交叉路口'];

  test('regionHash 相同时按图像 hash 绝对分与领先差双门槛收敛十字与环形',
      () async {
    QuizBankCache.instance.assign(const [
      QuizBankItem(
        id: 'cross',
        question: question,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: '十字交叉路口',
        imageRegionHash: 'aaaaaaaaaaaaaaaa',
        source: 'test',
      ),
      QuizBankItem(
        id: 'round',
        question: question,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: '环形交叉路口',
        imageRegionHash: 'bbbbbbbbbbbbbbbb',
        source: 'test',
      ),
    ]);

    final result = await engine().search(
      question,
      probeOptions: options,
      imagePerceptualHash: 'aaaaaaaaaaaaaaaa',
    );

    expect(result.isSuccess, isTrue);
    expect(result.answers.single.correctAnswer, '十字交叉路口');
    expect(result.answers.single.imageMatchHint, contains('题图消歧已启用'));
  });

  test('regionHash 匹配不足时明确提示框选问题，保留双候选要求确认',
      () async {
    QuizBankCache.instance.assign(const [
      QuizBankItem(
        id: 'cross',
        question: question,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: '十字交叉路口',
        imageRegionHash: 'aaaaaaaaaaaaaaaa',
        source: 'test',
      ),
      QuizBankItem(
        id: 'round',
        question: question,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: '环形交叉路口',
        imageRegionHash: 'bbbbbbbbbbbbbbbb',
        source: 'test',
      ),
    ]);

    // 给出两个题库区域 hash 都不近的 hash，模拟框选到题图上下无关内容。
    final result = await engine().search(
      question,
      probeOptions: options,
      imagePerceptualHash: 'cccccccccccccccc',
    );

    expect(result.isSuccess, isTrue);
    expect(
      result.answers.map((a) => a.correctAnswer).toSet(),
      containsAll(<String>{'十字交叉路口', '环形交叉路口'}),
    );
    expect(result.answers.first.imageMatchHint, contains('题图匹配不足'));
  });

  test('题库侧无 imageRegionHash 时不得用旧整题 hash 自动选答案', () async {
    QuizBankCache.instance.assign(const [
      QuizBankItem(
        id: 'legacy-a',
        question: question,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: '十字交叉路口',
        imagePerceptualHash: 'aaaaaaaaaaaaaaaa',
        source: 'test',
      ),
      QuizBankItem(
        id: 'legacy-b',
        question: question,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: '环形交叉路口',
        imagePerceptualHash: 'bbbbbbbbbbbbbbbb',
        source: 'test',
      ),
    ]);

    final result = await engine().search(
      question,
      probeOptions: options,
      imagePerceptualHash: 'aaaaaaaaaaaaaaaa',
    );

    expect(result.isSuccess, isTrue);
    expect(
      result.answers.map((a) => a.correctAnswer).toSet(),
      containsAll(<String>{'十字交叉路口', '环形交叉路口'}),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:box/features/quiz_plugin/data/quiz_engine.dart';

void main() {
  group('题干优先，同题再比选项', () {
    late QuizEngine engine;

    setUp(() {
      engine = QuizEngine(
        config: const QuizConfig(
          enabled: true,
          bankEnabled: true,
          autoSearch: false,
          allowExternalApi: false,
          bankMaxMatches: 5,
        ),
      );
      QuizBankCache.instance.assign([
        const QuizBankItem(
          id: 'a',
          question: '驾驶这种机动车上路行驶属于什么行为?',
          type: QuizQuestionType.singleChoice,
          options: ['违规行为', '违章行为', '违法行为', '犯罪行为'],
          correctAnswer: '违法行为',
          source: 'test',
        ),
        const QuizBankItem(
          id: 'b',
          question: '驾驶这种机动车上路行驶属于什么行为?',
          type: QuizQuestionType.singleChoice,
          options: ['正确', '错误'],
          correctAnswer: '正确',
          source: 'test',
        ),
        const QuizBankItem(
          id: 'c',
          question: '完全不同的另一道题干内容用于干扰',
          type: QuizQuestionType.singleChoice,
          options: ['违规行为', '违章行为', '违法行为', '犯罪行为'],
          correctAnswer: '违法行为',
          source: 'test',
        ),
      ]);
    });

    test('纯题干命中，相似度为题干分', () async {
      final r = await engine.search('驾驶这种机动车上路行驶属于什么行为?');
      expect(r.isSuccess, isTrue);
      expect(r.answers.first.text, contains('相似度：100%'));
      // 不应被干扰题（选项相同但题干不同）抢走
      expect(r.answers.first.correctAnswer, isNot(''));
      expect(r.answers.every((a) => a.text.contains('驾驶这种机动车')), isTrue);
    });

    test('同题干两条时用选项决胜', () async {
      final r = await engine.search(
        '驾驶这种机动车上路行驶属于什么行为?',
        probeOptions: ['违规行为', '违章行为', '违法行为', '犯罪行为'],
      );
      expect(r.isSuccess, isTrue);
      // 有卷面选项时投影为「C. 违法行为」
      expect(
        r.answers.first.correctAnswer,
        anyOf('违法行为', 'C. 违法行为'),
      );
      expect(r.answers.first.text, contains('选项决胜'));
    });

    test('同题干 + 判断选项命中另一条', () async {
      final r = await engine.search(
        '驾驶这种机动车上路行驶属于什么行为?',
        probeOptions: ['正确', '错误'],
      );
      expect(r.isSuccess, isTrue);
      expect(
        r.answers.first.correctAnswer,
        anyOf('正确', 'A. 正确'),
      );
    });

    test('同题干不同选项：完整选项只返回对应题，不能混入另一个变体', () async {
      final r = await engine.search(
        '驾驶这种机动车上路行驶属于什么行为?',
        probeOptions: const ['违规行为', '违章行为', '违法行为', '犯罪行为'],
      );
      expect(r.isSuccess, isTrue);
      expect(r.answers, hasLength(1));
      expect(
        r.answers.single.correctAnswer,
        anyOf('违法行为', 'C. 违法行为'),
      );
      expect(r.answers.single.options, const ['违规行为', '违章行为', '违法行为', '犯罪行为']);
    });

    test('选项再像也不会压过不同题干', () async {
      // 干扰题 c 选项与试捕完全一致，但题干不同
      final r = await engine.search(
        '驾驶这种机动车上路行驶属于什么行为?',
        probeOptions: ['违规行为', '违章行为', '违法行为', '犯罪行为'],
      );
      expect(r.isSuccess, isTrue);
      expect(r.answers.first.text, isNot(contains('完全不同的另一道')));
      expect(
        r.answers.first.correctAnswer,
        anyOf('违法行为', 'C. 违法行为'),
      );
    });
  });
}

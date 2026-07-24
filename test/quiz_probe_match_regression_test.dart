import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';

void main() {
  test('索引分词未命中时仍提供受限候选，避免题库已有题被漏掉', () {
    final items = List.generate(
      80,
      (i) => QuizBankItem(
        id: 'id_$i',
        question: i == 53 ? '夜间通过没有交通信号灯的路口应减速观察' : '其他交通规则第$i题',
        type: QuizQuestionType.singleChoice,
        options: const ['A', 'B'],
        correctAnswer: 'A',
      ),
    );
    final cache = QuizBankCache.forTesting(items);
    final candidates = cache.candidatesFor('夜间路口减速观察');
    expect(candidates, isNotEmpty);
    expect(candidates.length, lessThanOrEqualTo(80));
  });

  test('试捕题干略有缺失但选项完全一致时相似度应保持高分', () async {
    QuizBankCache.instance.assign([
      const QuizBankItem(
        id: 'night',
        question: '夜间通过没有交通信号灯的路口应当如何操作减速观察确保安全',
        type: QuizQuestionType.singleChoice,
        options: ['加速通过', '减速观察', '鸣笛通过', '停车等待'],
        correctAnswer: 'B',
      ),
    ]);
    final engine = QuizEngine(config: const QuizConfig(bankEnabled: true));
    final result = await engine.search(
      '夜间通过路口应当如何操作',
      probeOptions: const ['加速通过', '减速观察', '鸣笛通过', '停车等待'],
    );
    expect(result.isSuccess, isTrue);
    expect(result.answers.first.confidence, greaterThanOrEqualTo(0.9));
  });
}

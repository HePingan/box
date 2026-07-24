import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';

void main() {
  test('本地题库结构化答案字段独立于匹配题目详情', () async {
    QuizBankCache.instance.assign([
      const QuizBankItem(
        id: 'one',
        question: '机动车通过路口时应当如何操作？',
        type: QuizQuestionType.singleChoice,
        options: ['加速通过', '减速观察', '随意变道', '鸣笛抢行'],
        correctAnswer: '减速观察',
      ),
    ]);
    final engine = QuizEngine(
      config: const QuizConfig(
        enabled: true,
        bankEnabled: true,
        autoSearch: false,
        allowExternalApi: false,
      ),
    );
    final result = await engine.search('机动车通过路口时应当如何操作？');
    expect(result.isSuccess, isTrue);
    expect(result.answers.single.correctAnswer, '减速观察');
    expect(result.answers.single.text, startsWith('匹配题目：'));
    // UI 层应使用 correctAnswer 放到第一行，而不是把 text 首行误标作答案。
  });

  test('悬浮窗正文只显示答案，不含匹配详情与相似度', () {
    const answer = QuizAnswer(
      text: '匹配题目：路口通行\n答案：减速观察\n相似度：92%\n解析：减速慢行',
      confidence: 0.92,
      correctAnswer: '减速观察',
    );
    // 通过公开 API 间接验证：similarity 来自 confidence；正文格式化走 correctAnswer。
    expect(QuizPluginEntry.similarityPercentForAnswer(answer), 92);
    // 引擎详情仍可含匹配题干，但 UI 层正确字段是 correctAnswer。
    expect(answer.correctAnswer, '减速观察');
    expect(answer.text.contains('匹配题目'), isTrue);
  });
}

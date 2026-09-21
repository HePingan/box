import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';

/// 真机 1.18.11 (234) 报告回归：
///
/// 卷面（用户截图 2026-09-13 07:22）：
///   已取得C1准驾车型资格多久后可以申请增驾C6？
///   A.90天  B.30天  C.6个月  D.1年以上     （正确答案 D.1年以上）
///
/// 云端题库真实存在逐字一致的题：
///   q_yVekqQASpqQz / 已取得C1准驾车型资格多久后可以申请增驾C6？
///   options = ['30天','90天','6个月','1年以上'] / correctAnswer = '1年以上'
///
/// 但真机悬浮窗显示「请人工确认 / 候选1：2」——
/// 「2」来自另一道完全不同的题：
///   q_xHnUoeWPOiU2 / 已取得小型汽车准驾车型资格多少年以上，可以申请增加中型客车准驾车型？
///   options = ['1','2','3','5'] / correctAnswer = '2'
///
/// 即：题库里明明有满分题，引擎却把「增驾中型客车」当作匹配候选端了出来。
void main() {
  const c6Stem = '已取得C1准驾车型资格多久后可以申请增驾C6？';
  const c6Options = ['30天', '90天', '6个月', '1年以上'];

  /// 还原云端题库中真实存在的竞争题（中型客车 + 轻型牵引挂车）。
  List<QuizBankItem> realBank() => const [
        QuizBankItem(
          id: 'q_yVekqQASpqQz',
          question: c6Stem,
          type: QuizQuestionType.singleChoice,
          options: c6Options,
          correctAnswer: '1年以上',
        ),
        QuizBankItem(
          id: 'q_xHnUoeWPOiU2',
          question: '已取得小型汽车准驾车型资格多少年以上，可以申请增加中型客车准驾车型？',
          type: QuizQuestionType.singleChoice,
          options: ['1', '2', '3', '5'],
          correctAnswer: '2',
        ),
        QuizBankItem(
          id: 'q_4Qyb9K-pCBDS',
          question: '已取得驾驶小型汽车准驾车型资格多少年以上，可以申请增加中型客车准驾车型？',
          type: QuizQuestionType.singleChoice,
          options: ['1', '2', '3', '5'],
          correctAnswer: '2',
        ),
        QuizBankItem(
          id: 'q_zArcvhX_6AGC',
          question: '申请增驾轻型牵引挂车的，应取得驾驶小型汽车、小型自动挡汽车准驾车型资格几年以上？',
          type: QuizQuestionType.singleChoice,
          options: ['1', '2', '3', '5'],
          correctAnswer: '1',
        ),
      ];

  test('RED：题库存在逐字一致的 C6 题时，不得把「增驾中型客车」当候选', () async {
    QuizBankCache.instance.assign(realBank());
    final engine = QuizEngine(config: const QuizConfig(bankEnabled: true));

    final result = await engine.search(c6Stem, probeOptions: c6Options);

    expect(result.isSuccess, isTrue, reason: '库里逐字一致，应命中');
    final answers = result.answers.map((a) => a.correctAnswer).toList();
    expect(
      answers,
      contains('1年以上'),
      reason: '正确答案应来自逐字一致的 C6 题',
    );
    expect(
      answers,
      isNot(contains('2')),
      reason: '「2」是「增驾中型客车」的答案，属完全不同题，不得作为候选',
    );
  });

  test('RED：C6 题应给出高置信（>=0.9），不得落到「请人工确认」', () async {
    QuizBankCache.instance.assign(realBank());
    final engine = QuizEngine(config: const QuizConfig(bankEnabled: true));

    final result = await engine.search(c6Stem, probeOptions: c6Options);

    expect(result.answers, isNotEmpty);
    expect(
      result.answers.first.confidence,
      greaterThanOrEqualTo(0.9),
      reason: '题干逐字一致 + 选项逐字一致 = 满分题，不该低置信',
    );
  });
}

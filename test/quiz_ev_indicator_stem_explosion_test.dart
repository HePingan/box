// 回归：图题的「同题干爆炸」判定不能只看条数阈值。
//
// 真机证据（2026-09-13 13:32，App 1.18.17）：
//   题「驾驶电动汽车，图中指示灯亮起表示（ ）。」答案=充电系统故障
//   卷面选项 A正在充电 B动力蓄电池故障 C低荷电状态警告 D充电系统故障
//   插件端出：「候选1：减速慢行信号 / 候选2：变道信号」——完全不相关
//
// 真实题库核验（3616 条）：
//   该题干共 9 条，9 种互斥答案；其中 4 条选项集与卷面完全相同
//   → 4 条并列满分，无唯一赢家 → 端出任一候选即误导
//
// 教训：上一版护栏阈值 >=60 只拦住 243 条的标志题，
//       漏掉 9~17 条这一档（本截图正是 9 条档）。

import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 题「驾驶电动汽车，图中指示灯亮起表示（ ）。」真实题库的快照（9 条）。
List<QuizBankItem> evIndicatorBank() => const [
      // 与卷面选项集完全相同（顺序不同）—— 这张截图的题
      QuizBankItem(
        id: 'q_t828I3jUQzZm',
        question: '驾驶电动汽车，图中指示灯亮起表示（ ）。',
        type: QuizQuestionType.singleChoice,
        options: ['低荷电状态警告', '正在充电', '充电系统故障', '动力蓄电池故障'],
        correctAnswer: '充电系统故障',
      ),
      // 同选项集，但答案不同 → 并列满分
      QuizBankItem(
        id: 'q_LqrNuIASvqJb',
        question: '驾驶电动汽车，图中指示灯亮起表示（ ）。',
        type: QuizQuestionType.singleChoice,
        options: ['低荷电状态警告', '正在充电', '动力蓄电池故障', '驱动功率限制'],
        correctAnswer: '动力蓄电池故障',
      ),
      QuizBankItem(
        id: 'q_AREDVDi9qoVC',
        question: '驾驶电动汽车，图中指示灯亮起表示（ ）。',
        type: QuizQuestionType.singleChoice,
        options: ['动力蓄电池故障', '驱动功率限制', '正在充电', '低荷电状态警告'],
        correctAnswer: '正在充电',
      ),
      QuizBankItem(
        id: 'q_L-_36RVB2o1N',
        question: '驾驶电动汽车，图中指示灯亮起表示（ ）。',
        type: QuizQuestionType.singleChoice,
        options: ['低荷电状态警告', '正在充电', '动力蓄电池故障', '驱动功率限制'],
        correctAnswer: '低荷电状态警告',
      ),
      QuizBankItem(
        id: 'q_GzJktZZW2tf8',
        question: '驾驶电动汽车，图中指示灯亮起表示（ ）。',
        type: QuizQuestionType.singleChoice,
        options: ['胎压故障警告', '低荷电状态警告', '驱动电机故障', '系统故障'],
        correctAnswer: '胎压故障警告',
      ),
      QuizBankItem(
        id: 'q_QGx_OCWQWvJG',
        question: '驾驶电动汽车，图中指示灯亮起表示（ ）。',
        type: QuizQuestionType.singleChoice,
        options: ['驱动功率限制', '驱动电机故障', '动力蓄电池故障', '电机过热警告'],
        correctAnswer: '电机过热警告',
      ),
      QuizBankItem(
        id: 'q_fLD_Mam0TTn1',
        question: '驾驶电动汽车，图中指示灯亮起表示（ ）。',
        type: QuizQuestionType.singleChoice,
        options: ['低荷电状态警告', '动力蓄电池高温报警', '动力蓄电池故障', '驱动功率限制'],
        correctAnswer: '动力蓄电池高温报警',
      ),
      QuizBankItem(
        id: 'q_5FTwshw5bD1d',
        question: '驾驶电动汽车，图中指示灯亮起表示（ ）。',
        type: QuizQuestionType.singleChoice,
        options: ['驱动功率限制', '驱动电机故障', '动力蓄电池故障', '低荷电状态警告'],
        correctAnswer: '驱动电机故障',
      ),
      QuizBankItem(
        id: 'q__H905Yh3aSs-',
        question: '驾驶电动汽车，图中指示灯亮起表示（ ）。',
        type: QuizQuestionType.singleChoice,
        options: ['动力蓄电池故障', '低荷电状态警告', '驱动电机故障', '系统故障'],
        correctAnswer: '系统故障',
      ),
    ];

void main() {
  // 每个用例自行 assign，无需 clear

  test('截图题：9 条同题干 / 9 种答案 → 必须判为看题图，不端无关候选', () async {
    QuizBankCache.instance.assign(evIndicatorBank());
    final engine = QuizEngine(config: const QuizConfig(bankEnabled: true));

    // 卷面（截图）：A正在充电 B动力蓄电池故障 C低荷电状态警告 D充电系统故障
    final r = await engine.search(
      '驾驶电动汽车，图中指示灯亮起表示（ ）。',
      probeOptions: const ['正在充电', '动力蓄电池故障', '低荷电状态警告', '充电系统故障'],
    );

    // 便于诊断的真机日志
    // ignore: avoid_print
    print('[EV] success=${r.isSuccess} n=${r.answers.length} '
        'stemExplosion=${r.stemExplosion} count=${r.stemExplosionCount} '
        'answers=${r.answers}');

    expect(r.stemExplosion, isTrue,
        reason: '9 条同题干 / 9 种互斥答案，任何候选都是误导，必须判为看题图');
    expect(r.answers, isEmpty, reason: '绝不能端出「减速慢行信号」这类无关候选');

    final body = QuizPluginEntry.imageQuestionOverlayBody(r);
    expect(body, contains('看题图'));
    expect(body, isNot(contains('候选')));
    expect(body, isNot(contains('减速慢行信号')));
  });

  test('不误伤：题干有区分度（同题干仅 1 条）的题仍正常决胜', () async {
    QuizBankCache.instance.assign(const [
      QuizBankItem(
        id: 'q_uniq',
        question: '驾驶电动汽车出行前，应检查剩余电量。',
        type: QuizQuestionType.singleChoice,
        options: ['正确', '错误'],
        correctAnswer: '正确',
      ),
    ]);
    final engine = QuizEngine(config: const QuizConfig(bankEnabled: true));
    final r = await engine.search('驾驶电动汽车出行前，应检查剩余电量。');

    // ignore: avoid_print
    print('[UNIQ] success=${r.isSuccess} stemExplosion=${r.stemExplosion} '
        'answers=${r.answers}');
    expect(r.stemExplosion, isFalse);
    expect(r.answers, isNotEmpty);
  });
}

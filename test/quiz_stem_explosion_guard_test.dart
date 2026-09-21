import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';

/// RED 回归：同题干候选爆炸（标志题）不得端出误导候选。
///
/// 真机日志证据（2026-09-13 12:43，App 1.18.16 (239)）：
///
///   [QUIZ][W] PARSE parsed rawLines=8 lines=8 type=single_choice qLen=9
///             opts=4 answer=建议速度 sawOpt=false q="这个标志是何含义？"
///   [QUIZ][I] MATCH candidates scored cand=243 passed=243 bestQ=100
///   [QUIZ][W] MATCH score=55 q=100 o=0 w=0.00 base=55 shape=0 img=-1 qid=quiz_012038641281
///   [QUIZ][I] MATCH score=74 q=100 o=43 w=0.00 base=74 shape=0 img=-1 qid=quiz_00721f4011e0
///
/// 真实题库：3616 条中「这个标志是何含义？」独占 243 条（220 种不同答案，仅 4 条有图）。
/// 题干逐字相同 → qScore 全员 100 → 题干维度完全失效；卷面只抓到 1 个文字选项
/// （「建议速度」）→ probeOptNorm.length < 3，所有「选项消歧」快捷路径全部跳过 →
/// 243 条候选带着 220 种互斥答案挤进确认态，悬浮窗端出「陡坡路段」这类无关答案。
///
/// 期望：这种「同题干爆炸 + 选项对不上」的场景必须被识别为标志图题，
/// 不得把可能误导的候选答案端给用户。
void main() {
  // 复刻真机库：243 条同题干「这个标志是何含义？」，答案互不相同。
  List<QuizBankItem> explodedBank() {
    const real = [
      (['T形交叉路口', 'Y形交叉路口', '十字交叉路口', '环形交叉路口'], 'T形交叉路口'),
      (['左侧通行', '不准通行', '两侧通行', '右侧通行'], '右侧通行'),
      (['堤坝路', '上陡坡', '下陡坡', '连续上坡'], '下陡坡'),
      (['提醒车辆驾驶人前方有向上的陡坡路段', '提醒车辆驾驶人前方有向下的陡坡路段'], '提醒车辆驾驶人前方有向上的陡坡路段'),
      (['30km/h', '建议速度', '最低速度', '最高速度'], '30km/h'),
      (['建议速度', '最低速度', '最高速度', '限制速度'], '建议速度'),
    ];
    final items = <QuizBankItem>[];
    for (var i = 0; i < 6; i++) {
      items.add(QuizBankItem(
        id: 'q_sign_$i',
        question: '这个标志是何含义？',
        type: QuizQuestionType.singleChoice,
        options: real[i].$1,
        correctAnswer: real[i].$2,
      ));
    }
    // 补足至 243 条，模拟真实规模（答案各不相同）。
    for (var i = 6; i < 243; i++) {
      items.add(QuizBankItem(
        id: 'q_filler_$i',
        question: '这个标志是何含义？',
        type: QuizQuestionType.singleChoice,
        options: ['标志A$i', '标志B$i', '标志C$i', '标志D$i'],
        correctAnswer: '标志A$i',
      ));
    }
    return items;
  }

  test('RED: 243 条同题干标志题不得端出误导候选', () async {
    QuizBankCache.instance.assign(explodedBank());
    final engine = QuizEngine(config: const QuizConfig(bankEnabled: true));

    // 真机输入：题干「这个标志是何含义？」，OCR 只抓到 1 个文字选项「建议速度」
    final r = await engine.search(
      '这个标志是何含义？',
      // 真机日志：probeOpts=4（卷面确实 OCR 到 4 个文字选项），
      // 但最佳 oScore 仅 43 —— 标志题的卷面选项是按图而异的短文字，
      // 拼写相近（速度/标志类）却与库中任一选项集都对不齐，
      // 于是没有任何一条能靠选项胜出。
      probeOptions: const ['T形交叉路口', 'Y形交叉路口', '堤坝路', '上陡坡'],
    );

    final all = r.answers.map((a) => a.correctAnswer).toList();
    // ignore: avoid_print
    print('[RED] success=${r.isSuccess} n=${r.answers.length} '
        'stemExplosion=${r.stemExplosion} count=${r.stemExplosionCount} '
        'answers=${all.take(4).toList()}');

    // 同题干爆炸必须被显式识别，且不得端出任何互斥候选答案。
    expect(r.stemExplosion, isTrue,
        reason: '243 条同题干标志题未被识别为「候选爆炸」');
    expect(r.answers, isEmpty,
        reason: '爆炸场景仍返回了 ${r.answers.length} 条候选，会误导用户');
    expect(r.error, contains('题图'),
        reason: '提示语未引导用户对照题图作答');
  });

  test('护栏不误伤：同题干变体少（<阈值）的限速题仍正常决胜', () async {
    // 真实题库中「在图中高速公路行驶，车速不得高于/超过/低于」各 1 条，
    // 选项集互不相同（120/100/90/60 vs 100/110/120/90 vs 50/60/80/100），
    // 卷面选项能对齐 → oScore 高 → 绝不能触发爆炸护栏。
    const bank = <QuizBankItem>[
      QuizBankItem(
        id: 'q_hw_0',
        question: '在图中高速公路行驶，车速不得超过（ ）。',
        type: QuizQuestionType.singleChoice,
        options: ['120公里/小时', '100公里/小时', '90公里/小时', '60公里/小时'],
        correctAnswer: '120公里/小时',
      ),
      QuizBankItem(
        id: 'q_hw_1',
        question: '在图中高速公路行驶，车速不得高于（ ）。',
        type: QuizQuestionType.singleChoice,
        options: ['100公里/小时', '110公里/小时', '120公里/小时', '90公里/小时'],
        correctAnswer: '110公里/小时',
      ),
      QuizBankItem(
        id: 'q_hw_2',
        question: '在图中高速公路行驶，车速不得低于（ ）。',
        type: QuizQuestionType.singleChoice,
        options: ['50公里/小时', '60公里/小时', '80公里/小时', '100公里/小时'],
        correctAnswer: '60公里/小时',
      ),
    ];
    QuizBankCache.instance.assign(bank);
    final engine = QuizEngine(config: const QuizConfig(bankEnabled: true));
    final r = await engine.search(
      '在图中高速公路行驶，车速不得高于（ ）。',
      probeOptions: const ['100公里/小时', '110公里/小时', '120公里/小时', '90公里/小时'],
    );

    // ignore: avoid_print
    print('[HW] success=${r.isSuccess} stemExplosion=${r.stemExplosion} '
        'answer=${r.answers.map((a) => a.correctAnswer).toList()}');

    expect(r.stemExplosion, isFalse, reason: '限速题被误判为爆炸');
    expect(r.isSuccess, isTrue, reason: '限速题本应正常命中');
    expect(r.answers.first.correctAnswer, '110公里/小时');
  });


  test('浮层文案：爆炸态显示「看题图作答」且不含任何候选', () async {
    QuizBankCache.instance.assign(explodedBank());
    final engine = QuizEngine(config: const QuizConfig(bankEnabled: true));
    final r = await engine.search(
      '这个标志是何含义？',
      probeOptions: const ['T形交叉路口', 'Y形交叉路口', '堤坝路', '上陡坡'],
    );

    final decision = QuizPluginEntry.overlayDecisionForResult(r, const []);
    final body = QuizPluginEntry.imageQuestionOverlayBody(r);
    // ignore: avoid_print
    print('[UI] status=${decision.status}\n$body');

    expect(decision.status, 'imageQuestion');
    expect(body, contains('看题图'));
    expect(body, isNot(contains('候选')));
    expect(body, isNot(contains('陡坡')));
  });
}

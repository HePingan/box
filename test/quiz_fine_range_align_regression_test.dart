// 真实反馈（2026-09-06 20:01 试捕 + 19:27 悬浮窗截图）
//
// 卷面（驾考宝典 背题模式，65/2290）：
//   单选：申请人在道路上学习驾驶时，未按照公安机关交通管理部门指定的路线、
//         时间进行的，由公安机关交通管理部门对教练员或随车指导人员处多少元罚款?
//   A. 20元以上200元以下      ← 卷面已勾选（蓝底白勾），底部「答案 A」
//   B. 200元以上500元以下
//   C. 1000元以上2000元以下
//   D. 200元以上1000元以下
//
// 题库记录（驾驶理论题库-20260719，无图）：答案 = 20元以上200元以下（第 1 项）
//
// 真机实际：悬浮窗显示「答案：1000元以上2000元以下」= C，置信度 90%。
// 90% 正是 bank_index 兜底的置信度，且 C 与正确答案 A 的正文完全不同，
// 说明兜底把答案贴到了错误的序号上。
import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/domain/ocr_quiz_parser.dart';
import 'package:box/features/quiz_plugin/domain/quiz_answer_aligner.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';

/// 从悬浮窗整段展示文本里取出「答案：」那一行。
/// 展示文本同时含有完整选项列表，直接对整段做 contains 断言会被
/// 姊妹选项的金额字样误伤。
String _answerLine(String display) {
  for (final line in display.split('\n')) {
    final t = line.trim();
    if (t.startsWith('答案')) return t;
  }
  return display;
}

void main() {
  const question =
      '申请人在道路上学习驾驶时，未按照公安机关交通管理部门指定的路线、时间进行的，'
      '由公安机关交通管理部门对教练员或随车指导人员处多少元罚款?';

  // 题库四项（与后台详情页逐字一致）
  const bankOptions = <String>[
    '20元以上200元以下',
    '200元以上500元以下',
    '1000元以上2000元以下',
    '200元以上1000元以下',
  ];
  const bankAnswer = '20元以上200元以下';

  // 20:01 试捕的读屏原文（逐行，含题干两端噪声 x）
  const rawLines = <String>[
    '答题',
    '背题',
    '视频',
    'NEW',
    '设置',
    'x $question' 'x',
    '20元以上200元以下',
    '200元以上500元以下',
    '1000元以上2000元以下',
    '200元以上1000元以下',
    '答案 A',
    '速记口诀',
    '本题技巧',
    '学习驾驶，不按指定路线、时间.',
    '-',
    '试题详解',
    '有问题',
  ];

  test('读屏原文应解析出 4 个金额区间选项', () {
    final parsed = OcrQuizParser.parse(rawLines.join('\n'));
    expect(parsed.options.length, 4);
    expect(parsed.options, bankOptions);
  });

  test('卷面选项齐全时必须对齐到 A（真实卷面形态）', () {
    final a = QuizAnswerAligner.align(
      bankAnswer: bankAnswer,
      bankOptions: bankOptions,
      probeOptions: bankOptions,
    );
    expect(a.aligned, isTrue, reason: 'method=${a.method}');
    expect(a.optionLetter, 'A', reason: '实际得到 ${a.displayAnswer}');
    expect(a.displayAnswer, contains('20元以上200元以下'));
  });

  test('卷面漏捕被勾选的 A 时，不得把答案贴成 C（复现真机 90% 错答案）', () {
    // 勾选态的 A 读屏拿不到文字 → 卷面只剩 B/C/D
    final a = QuizAnswerAligner.align(
      bankAnswer: bankAnswer,
      bankOptions: bankOptions,
      probeOptions: const [
        '200元以上500元以下',
        '1000元以上2000元以下',
        '200元以上1000元以下',
      ],
    );
    // 关键断言：绝不能显示 C 的正文
    expect(
      a.displayAnswer,
      isNot(contains('1000元以上2000元以下')),
      reason: '真机误报为 C。实际 method=${a.method} score=${a.score} '
          'letter=${a.optionLetter} display=${a.displayAnswer}',
    );
    // 正确行为：补出 A，且正文是题库答案
    expect(a.optionLetter, 'A', reason: 'method=${a.method}');
    expect(a.displayAnswer, contains('20元以上200元以下'));
  });

  // 题库里存在一对姊妹题（真实数据，同步 API 核对）：
  //   q_4ynZD2xNTL5p 未按照…指定的路线、时间进行的      → 20元以上200元以下（A）
  //   q_4vIY6OBaBGLL 未使用符合规定的机动车              → 200元以上500元以下（B）
  // 四个选项完全相同，题干仅一处差异，答案不同。
  // 选材若走模糊题干相似度，两题极易互串，产生比选项误配更隐蔽的错答案。
  group('姊妹题选材（同选项集、题干一处差异、答案不同）', () {
    const sisterOptions = bankOptions;
    const qRoute =
        '申请人在道路上学习驾驶时，未按照公安机关交通管理部门指定的路线、时间进行的，'
        '由公安机关交通管理部门对教练员或随车指导人员处多少元罚款?';
    const qVehicle =
        '申请人在道路上学习驾驶时，未使用符合规定的机动车，'
        '由公安机关交通管理部门对教练员或者随车指导人员处多少元罚款?';

    void seed() {
      QuizBankCache.instance.assign(const [
        QuizBankItem(
          id: 'q_4ynZD2xNTL5p',
          question: qRoute,
          type: QuizQuestionType.singleChoice,
          options: sisterOptions,
          correctAnswer: '20元以上200元以下',
        ),
        QuizBankItem(
          id: 'q_4vIY6OBaBGLL',
          question: qVehicle,
          type: QuizQuestionType.singleChoice,
          options: sisterOptions,
          correctAnswer: '200元以上500元以下',
        ),
      ]);
    }

    test('「指定路线、时间」题必须命中 A，不得串到姊妹题的 B', () async {
      seed();
      final engine = QuizEngine(config: const QuizConfig(bankEnabled: true));
      final r = await engine.search(qRoute, probeOptions: sisterOptions);
      expect(r.isSuccess, isTrue);
      final a = r.answers.first;
      // text 是整段展示文本，含完整选项列表；只能校验「答案：」那一行，
      // 否则会被选项列表里的姊妹金额字样误伤。
      expect(
        _answerLine(a.text),
        contains('20元以上200元以下'),
        reason: '串题了：${a.text} (method=${a.alignmentMethod})',
      );
      expect(_answerLine(a.text), isNot(contains('200元以上500元以下')));
    });

    test('「未使用符合规定机动车」题必须命中 B，不得串到姊妹题的 A', () async {
      seed();
      final engine = QuizEngine(config: const QuizConfig(bankEnabled: true));
      final r = await engine.search(qVehicle, probeOptions: sisterOptions);
      expect(r.isSuccess, isTrue);
      final a = r.answers.first;
      expect(
        _answerLine(a.text),
        contains('200元以上500元以下'),
        reason: '串题了：${a.text} (method=${a.alignmentMethod})',
      );
      expect(_answerLine(a.text), isNot(contains('20元以上200元以下')));
    });
  });

  test('包含关系不得让短前缀答案误吞长选项（20元 vs 200元/1000元）', () {
    // 「20元以上200元以下」与「200元以上...」「1000元以上2000元...」
    // 存在大量公共子串，contains/similarity 极易误命中。
    for (final probe in <List<String>>[
      ['200元以上500元以下', '1000元以上2000元以下', '200元以上1000元以下'],
      ['1000元以上2000元以下', '200元以上1000元以下'],
    ]) {
      final a = QuizAnswerAligner.align(
        bankAnswer: bankAnswer,
        bankOptions: bankOptions,
        probeOptions: probe,
      );
      expect(
        a.displayAnswer,
        isNot(contains('1000元以上2000元以下')),
        reason: 'probe=$probe method=${a.method} display=${a.displayAnswer}',
      );
    }
  });
}

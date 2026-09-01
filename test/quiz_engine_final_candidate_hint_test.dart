import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用户真实反馈的题：「这个标志是何含义？」四个交叉路口选项。
/// 题图未形成明确领先时，不能把排序第一条静默当成正确答案。
void main() {
  const probeOptions = <String>['T形交叉路口', 'Y形交叉路口', '十字交叉路口', '环形交叉路口'];

  QuizBankItem exactVariant({
    required String id,
    required String answer,
    required String regionHash,
  }) => QuizBankItem(
    id: id,
    question: '这个标志是何含义？',
    type: QuizQuestionType.singleChoice,
    options: probeOptions,
    correctAnswer: answer,
    imageRegionHash: regionHash,
    source: 'test',
  );

  QuizBankItem otherOptionVariant({
    required String id,
    required List<String> options,
    required String answer,
    required String regionHash,
  }) => QuizBankItem(
    id: id,
    question: '这个标志是何含义？',
    type: QuizQuestionType.singleChoice,
    options: options,
    correctAnswer: answer,
    imageRegionHash: regionHash,
    source: 'test',
  );

  QuizEngine engine() => QuizEngine(
    config: const QuizConfig(
      enabled: true,
      bankEnabled: true,
      autoSearch: false,
      allowExternalApi: false,
      bankMaxMatches: 3,
    ),
  );

  final noise = <QuizBankItem>[
    otherOptionVariant(
      id: 'noise-ring-ahead',
      options: const ['环形交叉路口预告', '注意危险', '注意信号灯', '减速慢行'],
      answer: '环形交叉路口预告',
      regionHash: 'aaaaaaaaaaaaaaaa',
    ),
    otherOptionVariant(
      id: 'noise-crossing',
      options: const ['交叉路口', '丁字路口', '环岛', '人行横道'],
      answer: '交叉路口',
      regionHash: 'bbbbbbbbbbbbbbbb',
    ),
  ];

  test('同题干同选项且题图未明确领先时，保留十字和T形并要求确认', () async {
    QuizBankCache.instance.assign([
      exactVariant(
        id: 'cross',
        answer: '十字交叉路口',
        regionHash: '0f0f0f0f0f0f0f0f',
      ),
      exactVariant(
        id: 't-shape',
        answer: 'T形交叉路口',
        regionHash: '0f0f0f0f0f0f0f1f',
      ),
      ...noise,
    ]);

    final result = await engine().search(
      '这个标志是何含义？',
      probeOptions: probeOptions,
      imagePerceptualHash: '0f0f0f0f0f0f0f0e',
    );

    expect(result.isSuccess, isTrue);
    expect(
      result.answers.map((answer) => answer.correctAnswer).toSet(),
      containsAll(<String>{'十字交叉路口', 'T形交叉路口'}),
    );
    final decision = QuizPluginEntry.overlayDecisionForResult(
      result,
      result.answers.map((answer) => answer.correctAnswer).toList(),
    );
    expect(decision.status, 'ambiguous');
    expect(decision.answerKey, isNull);
  });

  test('视觉分数未达到可靠自动收敛阈值时，不得压成首条答案', () async {
    QuizBankCache.instance.assign([
      exactVariant(
        id: 'cross-low-visual',
        answer: '十字交叉路口',
        // 与 probe 相差约 19 bit，视觉分数约 70。
        regionHash: '000000000007ffff',
      ),
      exactVariant(
        id: 't-shape-low-visual',
        answer: 'T形交叉路口',
        // 与 probe 相差约 32 bit，视觉分数约 50。
        regionHash: 'ffffffffffffffff',
      ),
      ...noise,
    ]);

    final result = await engine().search(
      '这个标志是何含义？',
      probeOptions: probeOptions,
      imagePerceptualHash: '0000000000000000',
    );

    expect(result.isSuccess, isTrue);
    expect(result.answers.length, greaterThan(1));
    expect(
      result.answers.map((answer) => answer.correctAnswer).toSet(),
      containsAll(<String>{'十字交叉路口', 'T形交叉路口'}),
    );
    final decision = QuizPluginEntry.overlayDecisionForResult(
      result,
      result.answers.map((answer) => answer.correctAnswer).toList(),
    );
    expect(decision.status, 'ambiguous');
    expect(decision.answerKey, isNull);
  });

  test('未收敛时列出真实竞争答案，且不混入已淘汰的其它选项集变体', () async {
    QuizBankCache.instance.assign([
      exactVariant(
        id: 'cross',
        answer: '十字交叉路口',
        regionHash: '0f0f0f0f0f0f0f0f',
      ),
      exactVariant(
        id: 't-shape',
        answer: 'T形交叉路口',
        regionHash: '0f0f0f0f0f0f0f1f',
      ),
      ...noise,
    ]);

    final result = await engine().search(
      '这个标志是何含义？',
      probeOptions: probeOptions,
      imagePerceptualHash: '0f0f0f0f0f0f0f0e',
    );

    expect(result.isSuccess, isTrue);
    expect(result.answers.length, greaterThan(1));
    final hint = result.answers.first.imageMatchHint;
    expect(hint, contains('候选答案'));
    expect(hint, contains('十字交叉路口'));
    expect(hint, contains('T形交叉路口'));
    expect(hint, isNot(contains('环形交叉路口预告')));
  });
}

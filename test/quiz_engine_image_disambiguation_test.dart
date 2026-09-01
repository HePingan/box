import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    QuizBankCache.instance.assign([
      QuizBankItem(
        id: 'image-a',
        question: '如图所示标志的含义是什么？',
        type: QuizQuestionType.singleChoice,
        options: const ['注意行人', '注意儿童', '注意信号灯', '注意非机动车'],
        correctAnswer: '注意行人',
        imageRegionHash: '0000000000000000',
        source: 'test',
      ),
      QuizBankItem(
        id: 'image-b',
        question: '如图所示标志的含义是什么？',
        type: QuizQuestionType.singleChoice,
        options: const ['注意行人', '注意儿童', '注意信号灯', '注意非机动车'],
        correctAnswer: '注意儿童',
        imageRegionHash: 'ffffffffffffffff',
        source: 'test',
      ),
    ]);
  });

  QuizEngine engine() => QuizEngine(
    config: const QuizConfig(
      enabled: true,
      bankEnabled: true,
      autoSearch: false,
      allowExternalApi: false,
      bankMaxMatches: 1,
    ),
  );

  test('同文同选项题由截图 regionHash 选出视觉一致变体', () async {
    final result = await engine().search(
      '如图所示标志的含义是什么？',
      probeOptions: const ['注意行人', '注意儿童', '注意信号灯', '注意非机动车'],
      imagePerceptualHash: 'ffffffffffffffff',
    );

    expect(result.isSuccess, isTrue);
    expect(result.answers.single.correctAnswer, '注意儿童');
  });

  test('缩放或轻压缩后的近似 regionHash 仍命中原图变体', () async {
    final result = await engine().search(
      '如图所示标志的含义是什么？',
      probeOptions: const ['注意行人', '注意儿童', '注意信号灯', '注意非机动车'],
      // 相对 image-a 仅末位 1 bit 变化，模拟缩放/轻压缩后的视觉近似。
      imagePerceptualHash: '0000000000000001',
    );

    expect(result.isSuccess, isTrue);
    expect(result.answers.single.correctAnswer, '注意行人');
  });

  test('裁剪导致少量位变化时仍优先于不相干图变体', () async {
    final result = await engine().search(
      '如图所示标志的含义是什么？',
      probeOptions: const ['注意行人', '注意儿童', '注意信号灯', '注意非机动车'],
      // 相对 image-b 仅低 4 bits 变化；与 image-a 的距离远得多。
      imagePerceptualHash: 'fffffffffffffff0',
    );

    expect(result.isSuccess, isTrue);
    expect(result.answers.single.correctAnswer, '注意儿童');
  });

  test('无效 regionHash 时保留同文同选项的竞争答案，不静默取文字排序第一条',
      () async {
    final result = await engine().search(
      '如图所示标志的含义是什么？',
      probeOptions: const ['注意行人', '注意儿童', '注意信号灯', '注意非机动车'],
      imagePerceptualHash: 'not-a-valid-64-bit-dhash',
    );

    expect(result.isSuccess, isTrue);
    expect(
      result.answers.map((answer) => answer.correctAnswer).toSet(),
      containsAll(<String>{'注意行人', '注意儿童'}),
    );
  });

  test('未提供截图 regionHash 时保留同文同选项的竞争答案', () async {
    final result = await engine().search(
      '如图所示标志的含义是什么？',
      probeOptions: const ['注意行人', '注意儿童', '注意信号灯', '注意非机动车'],
    );

    expect(result.isSuccess, isTrue);
    expect(
      result.answers.map((answer) => answer.correctAnswer).toSet(),
      containsAll(<String>{'注意行人', '注意儿童'}),
    );
  });
}

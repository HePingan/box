import 'package:box/features/quiz_plugin/domain/quiz_answer_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('停车让行 projects to 停车等待 on probe options', () {
    final alignment = QuizAnswerAligner.align(
      bankAnswer: '停车让行',
      bankOptions: const ['在铁路道口掉头', '停车让行', '加速通过', '倒车'],
      probeOptions: const [
        '在铁路道口掉头',
        '停车等待',
        '无需观察，加速通过',
        '在铁路道口倒车',
      ],
    );

    expect(alignment.aligned, isTrue);
    expect(alignment.optionLetter, 'B');
    expect(alignment.displayAnswer, 'B. 停车等待');
    expect(
      alignment.method,
      anyOf('synonym', 'similarity', 'contains', 'token'),
    );
    expect(alignment.confidenceFactor, lessThan(1.0));
    expect(alignment.confidenceFactor, greaterThan(0.85));
  });

  test('pure letter does not hard-map when bank option text disagrees', () {
    // 题库只存 B，但 B 项正文与卷面 B 不同：不得硬贴卷面 B。
    final alignment = QuizAnswerAligner.align(
      bankAnswer: 'B',
      bankOptions: const ['A项', 'B项', 'C项', 'D项'],
      probeOptions: const [
        '在铁路道口掉头',
        '停车等待',
        '无需观察，加速通过',
        '在铁路道口倒车',
      ],
    );
    expect(alignment.aligned, isFalse);
    expect(alignment.method, 'bank_raw');
    expect(alignment.confidenceFactor, closeTo(0.70, 0.001));
  });

  test('letter maps when bank option content agrees with probe', () {
    final alignment = QuizAnswerAligner.align(
      bankAnswer: 'B',
      bankOptions: const [
        '在铁路道口掉头',
        '停车等待',
        '无需观察，加速通过',
        '在铁路道口倒车',
      ],
      probeOptions: const [
        '在铁路道口掉头',
        '停车等待',
        '无需观察，加速通过',
        '在铁路道口倒车',
      ],
    );
    expect(alignment.aligned, isTrue);
    expect(alignment.method, anyOf('letter', 'exact'));
    expect(alignment.displayAnswer, 'B. 停车等待');
  });

  test('unaligned answer keeps bank raw and lowers factor', () {
    final alignment = QuizAnswerAligner.align(
      bankAnswer: '鸣喇叭示意',
      bankOptions: const ['鸣喇叭示意', '加速通过'],
      probeOptions: const [
        '在铁路道口掉头',
        '停车等待',
        '无需观察，加速通过',
        '在铁路道口倒车',
      ],
    );
    expect(alignment.aligned, isFalse);
    expect(alignment.displayAnswer, '鸣喇叭示意');
    expect(alignment.confidenceFactor, closeTo(0.70, 0.001));
  });

  test('exact option text alignment', () {
    final alignment = QuizAnswerAligner.align(
      bankAnswer: '停车等待',
      bankOptions: const ['停车等待'],
      probeOptions: const ['在铁路道口掉头', '停车等待', '加速通过', '倒车'],
    );
    expect(alignment.aligned, isTrue);
    expect(alignment.method, 'exact');
    expect(alignment.displayAnswer, 'B. 停车等待');
  });

  test('image-choice bank answer does not map onto text options', () {
    final alignment = QuizAnswerAligner.align(
      bankAnswer: 'A. 图1',
      bankOptions: const ['图1', '图2', '图3', '图4'],
      probeOptions: const [
        '驾驶未悬挂机动车号牌或者故意遮挡、污损机动车号牌的机动车上道路行驶的',
        '驾驶机动车在高速公路上行驶低于规定最低时速的',
        '造成致人轻微伤或者财产损失的交通事故后逃逸，尚不构成犯罪的',
        '造成致人轻伤以上或者死亡的交通事故后逃逸，尚不构成犯罪的',
      ],
    );
    expect(alignment.aligned, isFalse);
    expect(alignment.displayAnswer, anyOf('图1', 'A. 图1'));
    expect(alignment.method, 'bank_raw');
  });

  test('letter maps only when bank option content agrees', () {
    final alignment = QuizAnswerAligner.align(
      bankAnswer: 'A',
      bankOptions: const [
        '驾驶未悬挂机动车号牌或者故意遮挡、污损机动车号牌的机动车上道路行驶的',
        '驾驶机动车在高速公路上行驶低于规定最低时速的',
        '造成致人轻微伤或者财产损失的交通事故后逃逸，尚不构成犯罪的',
        '造成致人轻伤以上或者死亡的交通事故后逃逸，尚不构成犯罪的',
      ],
      probeOptions: const [
        '驾驶未悬挂机动车号牌或者故意遮挡、污损机动车号牌的机动车上道路行驶的',
        '驾驶机动车在高速公路上行驶低于规定最低时速的',
        '造成致人轻微伤或者财产损失的交通事故后逃逸，尚不构成犯罪的',
        '造成致人轻伤以上或者死亡的交通事故后逃逸，尚不构成犯罪的',
      ],
    );
    expect(alignment.aligned, isTrue);
    expect(alignment.optionLetter, 'A');
    expect(alignment.displayAnswer.startsWith('A. '), isTrue);
  });

  test('short bank answer maps into longer probe option', () {
    final alignment = QuizAnswerAligner.align(
      bankAnswer: '放置距离不足',
      bankOptions: const [
        '未开启危险报警闪光灯',
        '警告标志放置距离不足150米',
        '车上人员未转移到安全区域',
      ],
      probeOptions: const [
        '①未开启危险报警闪光灯',
        '②警告标志放置距离不足150米',
        '③车上人员未转移到安全区域',
      ],
    );
    expect(alignment.aligned, isTrue);
    expect(alignment.optionLetter, 'B');
    expect(alignment.displayAnswer.contains('警告标志放置距离不足'), isTrue);
    expect(alignment.confidenceFactor, greaterThan(0.85));
  });

  test('circled multi-select ①②③ projects to probe options', () {
    final alignment = QuizAnswerAligner.align(
      bankAnswer: '①②③',
      bankOptions: const [
        '未开启危险报警闪光灯',
        '警告标志放置距离不足150米',
        '车上人员未转移到安全区域',
      ],
      probeOptions: const [
        '①未开启危险报警闪光灯',
        '②警告标志放置距离不足150米',
        '③车上人员未转移到安全区域',
      ],
    );
    expect(alignment.aligned, isTrue);
    expect(alignment.method, 'multi');
    expect(alignment.optionLetter, 'ABC');
    expect(alignment.displayAnswer.startsWith('ABC. '), isTrue);
    expect(alignment.confidenceFactor, greaterThan(0.90));
  });

  test('synonym emergency-lane phrases align', () {
    final alignment = QuizAnswerAligner.align(
      bankAnswer: '未开启危险报警闪光灯',
      bankOptions: const [
        '未开启危险报警闪光灯',
        '警告标志放置距离不足150米',
        '车上人员未转移到安全区域',
      ],
      probeOptions: const [
        '未打开双闪',
        '三角牌距离不足',
        '未撤离到安全区域',
      ],
    );
    expect(alignment.aligned, isTrue);
    expect(alignment.optionLetter, 'A');
    expect(alignment.method, anyOf('synonym', 'similarity', 'contains', 'token'));
  });
}

import 'package:box/features/quiz_plugin/domain/quiz_answer_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

/// 引擎内「非看图题拒收图N」与对齐器联动的回归用例。
void main() {
  const textOptions = [
    '驾驶未悬挂机动车号牌或者故意遮挡、污损机动车号牌的机动车上道路行驶的',
    '驾驶机动车在高速公路上行驶低于规定最低时速的',
    '造成致人轻微伤或者财产损失的交通事故后逃逸，尚不构成犯罪的',
    '造成致人轻伤以上或者死亡的交通事故后逃逸，尚不构成犯罪的',
  ];

  test('图选题答案在文字卷面不得对齐成功', () {
    final a = QuizAnswerAligner.align(
      bankAnswer: 'A. 图1',
      bankOptions: const ['图1', '图2', '图3', '图4'],
      probeOptions: textOptions,
    );
    expect(a.aligned, isFalse);
    expect(a.displayAnswer.contains('图1'), isTrue);
    expect(a.displayAnswer.contains('未悬挂'), isFalse);
  });

  test('文字题正确答案可对齐到卷面 A', () {
    final a = QuizAnswerAligner.align(
      bankAnswer: 'A',
      bankOptions: textOptions,
      probeOptions: textOptions,
    );
    expect(a.aligned, isTrue);
    expect(a.optionLetter, 'A');
    expect(a.displayAnswer.startsWith('A. '), isTrue);
    expect(a.displayAnswer.contains('未悬挂'), isTrue);
  });
}

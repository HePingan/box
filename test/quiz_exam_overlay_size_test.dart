import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';

void main() {
  test('考试窗尺寸默认标准', () {
    expect(const QuizConfig().examOverlaySize, 'standard');
  });

  test('考试窗尺寸序列化并兼容非法值', () {
    const large = QuizConfig(examOverlaySize: 'large');
    expect(QuizConfig.fromJson(large.toJson()).examOverlaySize, 'large');
    expect(QuizConfig.fromJson({'examOverlaySize': 'invalid'}).examOverlaySize,
        'standard');
  });
}

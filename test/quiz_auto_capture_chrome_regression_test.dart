import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:box/features/quiz_plugin/domain/quiz_config.dart';
import 'package:box/features/quiz_plugin/data/quiz_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('自动读屏混入顶部 chrome 时仍用解析出的题干命中本地题库', () async {
    QuizBankCache.instance.assign([
      const QuizBankItem(
        id: 'unlicensed-driving',
        question: '对未取得驾驶证驾驶机动车的，追究其法律责任。',
        type: QuizQuestionType.trueFalse,
        options: ['正确', '错误'],
        correctAnswer: '正确',
      ),
    ]);
    const captured = '''
答题
背题
视频
设置
判断
对未取得驾驶证驾驶机动车的，
追究其法律责任。
读题
正确
错误
收藏
1/2213
''';

    final result = await QuizEngine(
      config: const QuizConfig(bankEnabled: true),
    ).search(captured);

    expect(result.isSuccess, isTrue);
    expect(result.answers.single.correctAnswer, '正确');
    expect(result.answers.single.source, '本地题库');
  });
}

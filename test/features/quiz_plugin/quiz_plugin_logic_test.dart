import 'package:box/features/quiz_plugin/quiz_bank.dart';
import 'package:box/features/quiz_plugin/quiz_config.dart';
import 'package:box/features/quiz_plugin/quiz_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuizBankTextNormalizer', () {
    test('removes ASCII parenthesized hints from question stems', () {
      final cleaned = QuizBankTextNormalizer.cleanForMatch('第1题（单选题）驾驶机动车(安全驾驶)时应当如何操作？');

      expect(cleaned, '驾驶机动车时应当如何操作？');
    });

    test('drops option and answer noise lines before matching', () {
      final cleaned = QuizBankTextNormalizer.cleanForMatch('题目：下列说法正确的是？\nA. 错误项\nB. 正确项\n正确答案：B');

      expect(cleaned, '下列说法正确的是？');
    });
  });

  group('UniqueQuizKeyGenerator', () {
    test('generates deterministic keys from normalized question text', () {
      final first = UniqueQuizKeyGenerator.key(' 下列说法正确的是？ ');
      final second = UniqueQuizKeyGenerator.key('下列  说法\n正确的是？');

      expect(first, second);
      expect(first, startsWith('quiz_'));
    });
  });

  group('QuizEngine', () {
    test('manual search can bypass disabled auto search after local miss', () async {
      QuizBankCache.instance.assign(const []);
      final engine = QuizEngine(
        config: const QuizConfig(
          autoSearch: false,
          bankEnabled: true,
          allowExternalApi: false,
        ),
      );

      final automatic = await engine.search('不存在的题目');
      final manual = await engine.search('不存在的题目', forceExternalSearch: true);

      expect(automatic.error, '未开启自动搜题');
      expect(manual.error, '本地题库未找到；外部搜题已关闭');
    });
  });
}

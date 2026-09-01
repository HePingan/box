import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';

void main() {
  group('UniqueQuizKeyGenerator', () {
    test('同题干不同选项 → 不同 id', () {
      const q = '驾驶这种机动车上路行驶属于什么行为?';
      final id1 = UniqueQuizKeyGenerator.key(
        q,
        options: ['违规行为', '违章行为', '违法行为', '犯罪行为'],
      );
      final id2 = UniqueQuizKeyGenerator.key(q, options: ['正确', '错误']);
      expect(id1, isNot(equals(id2)));
    });

    test('同题干同选项（顺序不同）→ 同一 id', () {
      const q = '以下说法正确的是？';
      final id1 = UniqueQuizKeyGenerator.key(q, options: ['A', 'B', 'C']);
      final id2 = UniqueQuizKeyGenerator.key(q, options: ['C', 'A', 'B']);
      expect(id1, equals(id2));
    });

    test('同题干同选项 → 覆盖同一 id', () {
      const q = '测试题';
      final opts = ['甲', '乙'];
      final a = UniqueQuizKeyGenerator.key(q, options: opts);
      final b = UniqueQuizKeyGenerator.key(q, options: opts);
      expect(a, equals(b));
    });

    test('同文同选项不同题图感知哈希 → 不同变体 id', () {
      const question = '这个标志是何含义？';
      const options = ['前方上坡', '上陡坡', '下陡坡'];
      final uphill = UniqueQuizKeyGenerator.key(
        question,
        options: options,
        imagePerceptualHash: '00112233445566778899aabbccddeeff',
      );
      final downhill = UniqueQuizKeyGenerator.key(
        question,
        options: options,
        imagePerceptualHash: 'ffeeddccbbaa99887766554433221100',
      );

      expect(uphill, isNot(equals(downhill)));
    });

    test('OCR 题图区域 hash 参与唯一身份，同文同选项不同图可并存', () {
      const question = '这个标志是何含义？';
      const options = ['T形交叉路口', 'Y形交叉路口', '十字交叉路口', '环形交叉路口'];
      final cross = UniqueQuizKeyGenerator.key(
        question,
        options: options,
        correctAnswer: '十字交叉路口',
        imageRegionHash: '0011223344556677',
      );
      final roundabout = UniqueQuizKeyGenerator.key(
        question,
        options: options,
        correctAnswer: '十字交叉路口',
        imageRegionHash: 'ffeeddccbbaa9988',
      );

      expect(cross, isNot(equals(roundabout)));
    });

    test('题图区域 hash 优先于旧整图 hash 作为变体身份', () {
      const question = '这个标志是何含义？';
      const options = ['T形交叉路口', 'Y形交叉路口', '十字交叉路口', '环形交叉路口'];
      final first = UniqueQuizKeyGenerator.key(
        question,
        options: options,
        imagePerceptualHash: 'aaaaaaaaaaaaaaaa',
        imageRegionHash: '0011223344556677',
      );
      final second = UniqueQuizKeyGenerator.key(
        question,
        options: options,
        imagePerceptualHash: 'aaaaaaaaaaaaaaaa',
        imageRegionHash: 'ffeeddccbbaa9988',
      );

      expect(first, isNot(equals(second)));
    });

    test('同一题图不同 URL 以感知哈希保持同一变体 id', () {
      const question = '这个标志是何含义？';
      const options = ['前方上坡', '上陡坡', '下陡坡'];
      final first = UniqueQuizKeyGenerator.key(
        question,
        options: options,
        imageSha256: 'a' * 64,
        imagePerceptualHash: '00112233445566778899aabbccddeeff',
      );
      final cachedCopy = UniqueQuizKeyGenerator.key(
        question,
        options: options,
        imageSha256: 'b' * 64,
        imagePerceptualHash: '00112233445566778899aabbccddeeff',
      );

      expect(first, equals(cachedCopy));
    });

    test('旧题无图片指纹时维持文字身份', () {
      const question = '这个标志是何含义？';
      const options = ['前方上坡', '上陡坡', '下陡坡'];
      expect(
        UniqueQuizKeyGenerator.key(question, options: options),
        equals(UniqueQuizKeyGenerator.key(question, options: options)),
      );
    });
  });

  test('图片指纹在 JSON 与数据库映射中往返保留', () {
    const sha256 =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const perceptualHash = '00112233445566778899aabbccddeeff';
    const item = QuizBankItem(
      id: 'variant',
      question: '这个标志是何含义？',
      type: QuizQuestionType.singleChoice,
      options: ['A', 'B'],
      correctAnswer: 'B',
      imageUrl: 'https://example.test/sign.png',
      imageSha256: sha256,
      imagePerceptualHash: perceptualHash,
    );

    final fromJson = QuizBankItem.fromJson(item.toJson());
    final fromDb = QuizBankItem.fromDb(item.toDb());

    expect(fromJson.imageSha256, item.imageSha256);
    expect(fromJson.imagePerceptualHash, item.imagePerceptualHash);
    expect(fromDb.imageSha256, item.imageSha256);
    expect(fromDb.imagePerceptualHash, item.imagePerceptualHash);
  });
}

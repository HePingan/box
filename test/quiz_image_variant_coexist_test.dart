import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('同文不同图题并存 — 纯域逻辑', () {
    const text = '下列哪项属于机动车驾驶违法行为？';
    const options = ['A. 开车时使用手机', 'B. 系好安全带', 'C. 保持车距', 'D. 遵守交通信号灯'];

    test('不同图指纹产生不同 id', () {
      const itemA = QuizBankItem(
        id: 'test_a',
        question: text,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: 'A',
        imageSha256: 'sha256_image_a',
        imagePerceptualHash: null,
      );
      const itemB = QuizBankItem(
        id: 'test_b',
        question: text,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: 'A',
        imageSha256: 'sha256_image_b',
        imagePerceptualHash: null,
      );

      expect(
        UniqueQuizKeyGenerator.keyFromItem(itemA),
        isNot(equals(UniqueQuizKeyGenerator.keyFromItem(itemB))),
      );
    });

    test('相同图指纹产生相同 id', () {
      const pHash = 'perceptual_hash_123';
      const itemA = QuizBankItem(
        id: 'test_a',
        question: text,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: 'A',
        imagePerceptualHash: pHash,
      );
      const itemB = QuizBankItem(
        id: 'test_b',
        question: text,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: 'A',
        imagePerceptualHash: pHash,
      );

      expect(
        UniqueQuizKeyGenerator.keyFromItem(itemA),
        equals(UniqueQuizKeyGenerator.keyFromItem(itemB)),
      );
    });

    test('无图指纹时维持旧文字身份', () {
      const itemA = QuizBankItem(
        id: 'test_a',
        question: text,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: 'A',
      );
      const itemB = QuizBankItem(
        id: 'test_b',
        question: text,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: 'A',
      );

      expect(
        UniqueQuizKeyGenerator.keyFromItem(itemA),
        equals(UniqueQuizKeyGenerator.keyFromItem(itemB)),
      );
    });

    test('图片指纹优先级：perceptualHash > sha256 > 文字', () {
      const itemPHash = QuizBankItem(
        id: 'test_ph',
        question: text,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: 'A',
        imagePerceptualHash: 'phash',
      );
      const itemSha256 = QuizBankItem(
        id: 'test_sha',
        question: text,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: 'A',
        imageSha256: 'sha256',
      );
      const itemTextOnly = QuizBankItem(
        id: 'test_text',
        question: text,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: 'A',
      );

      // 有 pHash 的与有 sha256 的不同
      expect(
        UniqueQuizKeyGenerator.keyFromItem(itemPHash),
        isNot(equals(UniqueQuizKeyGenerator.keyFromItem(itemSha256))),
      );
      // 有 sha256 的与只有文字的也不同
      expect(
        UniqueQuizKeyGenerator.keyFromItem(itemSha256),
        isNot(equals(UniqueQuizKeyGenerator.keyFromItem(itemTextOnly))),
      );
      // 无图指纹的与有图指纹的不同
      expect(
        UniqueQuizKeyGenerator.keyFromItem(itemTextOnly),
        isNot(equals(UniqueQuizKeyGenerator.keyFromItem(itemPHash))),
      );
    });
  });

  group('同文不同图题 — QuizBankWritePolicy 域逻辑', () {
    const text = '下列哪项属于机动车驾驶违法行为？';
    const options = ['A. 开车时使用手机', 'B. 系好安全带', 'C. 保持车距', 'D. 遵守交通信号灯'];

    test('不同图指纹题可并存于写入决策', () {
      const itemA = QuizBankItem(
        id: 'test_a',
        question: text,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: 'A',
        imageSha256: 'sha256_a',
      );
      const itemB = QuizBankItem(
        id: 'test_b',
        question: text,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: 'A',
        imageSha256: 'sha256_b',
      );

      final decisionA = QuizBankWritePolicy.insertIfAbsent(
        existing: const [],
        incoming: itemA,
      );
      expect(decisionA.status, QuizBankWriteStatus.inserted);
      expect(decisionA.items.length, 1);

      final decisionB = QuizBankWritePolicy.insertIfAbsent(
        existing: decisionA.items,
        incoming: itemB,
      );
      // 不同图指纹 → variantInserted（同题干不同图）
      expect(decisionB.status, QuizBankWriteStatus.variantInserted);
      expect(decisionB.items.length, 2);
    });

    test('相同图指纹题写入被跳过', () {
      const pHash = 'perceptual_hash_123';
      const itemA = QuizBankItem(
        id: 'test_a',
        question: text,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: 'A',
        imagePerceptualHash: pHash,
      );
      const itemB = QuizBankItem(
        id: 'test_b',
        question: text,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: 'A',
        imagePerceptualHash: pHash,
      );

      final decisionA = QuizBankWritePolicy.insertIfAbsent(
        existing: const [],
        incoming: itemA,
      );
      expect(decisionA.status, QuizBankWriteStatus.inserted);

      final decisionB = QuizBankWritePolicy.insertIfAbsent(
        existing: decisionA.items,
        incoming: itemB,
      );
      // 相同图指纹 → duplicateSkipped
      expect(decisionB.status, QuizBankWriteStatus.duplicateSkipped);
      expect(decisionB.items.length, 1);
    });

    test('OCR 录入只有题图区域 hash 时，不同图片仍作为两个变体保存', () {
      const itemA = QuizBankItem(
        id: 'ocr_a',
        question: text,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: 'A',
        imageRegionHash: '0011223344556677',
      );
      const itemB = QuizBankItem(
        id: 'ocr_b',
        question: text,
        type: QuizQuestionType.singleChoice,
        options: options,
        correctAnswer: 'A',
        imageRegionHash: 'ffeeddccbbaa9988',
      );

      final first = QuizBankWritePolicy.insertIfAbsent(
        existing: const [],
        incoming: itemA,
      );
      final second = QuizBankWritePolicy.insertIfAbsent(
        existing: first.items,
        incoming: itemB,
      );

      expect(second.status, QuizBankWriteStatus.variantInserted);
      expect(second.items, hasLength(2));
    });
  });
}

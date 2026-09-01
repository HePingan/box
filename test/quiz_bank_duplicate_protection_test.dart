import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:flutter_test/flutter_test.dart';

QuizBankItem item({
  required String id,
  required String question,
  List<String> options = const ['甲', '乙'],
  String answer = '甲',
  String? analysis,
  DateTime? createdAt,
}) => QuizBankItem(
  id: id,
  question: question,
  type: QuizQuestionType.singleChoice,
  options: options,
  correctAnswer: answer,
  analysis: analysis,
  createdAt: createdAt,
);

void main() {
  group('QuizBank duplicate protection', () {
    test(
      'same canonical question (including answer) is rejected without replacing stored content',
      () {
        final existing = item(
          id: 'old',
          question: '夜间会车应使用什么灯光？',
          options: const ['近光灯', '远光灯'],
          answer: '近光灯',
          analysis: '会车使用近光灯。',
        );
        final incoming = item(
          id: 'new',
          question: '夜间 会车应使用什么灯光？',
          options: const ['远光灯', '近光灯'],
          answer: '近光灯', // 相同答案
        );

        final result = QuizBankWritePolicy.insertIfAbsent(
          existing: [existing],
          incoming: incoming,
        );

        expect(result.status, QuizBankWriteStatus.duplicateSkipped);
        expect(result.items, hasLength(1));
        expect(result.items.single.correctAnswer, '近光灯');
        expect(result.items.single.analysis, '会车使用近光灯。');
      },
    );

    test('same stem with different answers is inserted as variant', () {
      final existing = item(id: 'old', question: '这是合法的吗？', answer: '甲');
      final incoming = item(
        id: 'new',
        question: '这是合法的吗？',
        options: const ['正确', '错误'],
        answer: '乙', // 不同答案
      );

      final result = QuizBankWritePolicy.insertIfAbsent(
        existing: [existing],
        incoming: incoming,
      );

      // 同题干+选项但答案不同：作为新变体插入（length 2）
      expect(
        result.status,
        anyOf(
          QuizBankWriteStatus.inserted,
          QuizBankWriteStatus.variantInserted,
        ),
      );
      expect(result.items, hasLength(2));
      expect(result.items.where((e) => e.correctAnswer == '甲'), hasLength(1));
      expect(result.items.where((e) => e.correctAnswer == '乙'), hasLength(1));
    });
  });

  group('QuizBank deduplicate', () {
    test(
      'keeps the most complete record for duplicate canonical questions',
      () {
        // 相同答案的题目才会被 deduplicate
        final result = QuizBankDeduplicator.deduplicate([
          item(
            id: 'legacy-a',
            question: '安全距离是多少？',
            answer: '',
            createdAt: DateTime(2026, 1, 2),
          ),
          item(
            id: 'legacy-b',
            question: '安全距离是多少？',
            answer: '', // 相同空答案，会合并
            analysis: '应根据车速和路况保持距离。',
            createdAt: DateTime(2026, 1, 3),
          ),
        ]);

        expect(result.items, hasLength(1));
        expect(result.removed, 1);
        expect(result.duplicateGroups, 1);
        expect(result.items.single.correctAnswer, '');
        expect(result.items.single.analysis, isNotEmpty);
        expect(
          result.items.single.id,
          UniqueQuizKeyGenerator.key(
            '安全距离是多少？',
            options: const ['甲', '乙'],
            correctAnswer: '',
          ),
        );
      },
    );
  });
}

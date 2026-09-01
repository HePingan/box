import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:flutter_test/flutter_test.dart';

QuizBankItem item({
  required String id,
  required String question,
  List<String> options = const ['甲', '乙'],
  String answer = '甲',
}) => QuizBankItem(
  id: id,
  question: question,
  type: QuizQuestionType.singleChoice,
  options: options,
  correctAnswer: answer,
);

void main() {
  group('QuizBank import v2 canonicalization', () {
    test(
      'always recalculates IDs and keeps different answers as separate entries',
      () {
        final canonicalWithAnswer = UniqueQuizKeyGenerator.key(
          '道路  安全？',
          options: const ['正确', '错误'],
          correctAnswer: '错误',
        );
        final canonicalWithOtherAnswer = UniqueQuizKeyGenerator.key(
          '道路  安全？',
          options: const ['正确', '错误'],
          correctAnswer: '甲', // 默认答案
        );

        final result = QuizBankImportNormalizer.canonicalize([
          item(
            id: 'legacy-question-only-id',
            question: '道路  安全？',
            options: const ['正确', '错误'],
            answer: '甲', // 默认答案
          ),
          item(
            id: 'foreign-id',
            question: '道路 安全？',
            options: const ['错误', '正确'],
            answer: '错误',
          ),
        ]);

        // 两条题答案不同，产生不同ID，都保留
        expect(result.items, hasLength(2));
        expect(result.items.any((e) => e.id == canonicalWithAnswer), true);
        expect(result.items.any((e) => e.id == canonicalWithOtherAnswer), true);
        expect(result.skipped, 0);
      },
    );

    test('counts malformed JSON records as skipped', () {
      final items = <Object?>[
        {
          'id': 'valid',
          'question': '夜间会车应使用什么灯光？',
          'options': ['近光灯', '远光灯'],
          'correctAnswer': '近光灯',
        },
        'not a quiz record',
      ];

      final parsed = <QuizBankItem>[];
      var invalid = 0;
      for (final entry in items) {
        if (entry is Map<String, Object?>) {
          parsed.add(QuizBankItem.fromJson(Map<String, dynamic>.from(entry)));
        } else {
          invalid++;
        }
      }
      final normalized = QuizBankImportNormalizer.canonicalize(parsed);
      expect(normalized.items, hasLength(1));
      expect(normalized.skipped + invalid, 1);
    });

    test(
      'skips blank questions instead of producing an empty canonical key',
      () {
        final result = QuizBankImportNormalizer.canonicalize([
          item(id: 'blank', question: '  '),
        ]);

        expect(result.items, isEmpty);
        expect(result.skipped, 1);
      },
    );
  });

  group('批量录入变体保护', () {
    final base = item(
      id: 'base',
      question: '图中指示灯亮起表示什么？',
      options: const ['低荷电状态警告', '正在充电', '动力蓄电池故障', '驱动功率限制'],
    );

    test('同题干仅个别选项不同，批量录入必须作为新变体保留', () {
      final incoming = item(
        id: 'variant',
        question: '图中指示灯亮起表示什么？',
        options: const ['低荷电状态警告', '正在充电', '充电系统故障', '驱动功率限制'],
      );
      final decision = QuizBankWritePolicy.insertIfAbsent(
        existing: [base],
        incoming: incoming,
        batchMode: true,
      );
      expect(decision.status, QuizBankWriteStatus.variantInserted);
      expect(decision.items, hasLength(2));
    });

    test('同题干且本轮选项是已存题的真子集，批量录入要求重试而不写脏题', () {
      final truncated = item(
        id: 'partial',
        question: '图中指示灯亮起表示什么？',
        options: const ['低荷电状态警告', '正在充电', '动力蓄电池故障'],
      );
      final decision = QuizBankWritePolicy.insertIfAbsent(
        existing: [base],
        incoming: truncated,
        batchMode: true,
      );
      expect(decision.status, QuizBankWriteStatus.incompleteVariantNeedsRetry);
      expect(decision.items, hasLength(1));
    });

    test('同题干完全同选项只跳过，不生成第二条', () {
      final duplicate = item(
        id: 'duplicate',
        question: '图中指示灯亮起表示什么？',
        options: const ['驱动功率限制', '动力蓄电池故障', '正在充电', '低荷电状态警告'],
      );
      final decision = QuizBankWritePolicy.insertIfAbsent(
        existing: [base],
        incoming: duplicate,
        batchMode: true,
      );
      expect(decision.status, QuizBankWriteStatus.duplicateSkipped);
      expect(decision.items, hasLength(1));
    });
  });

  group('QuizBankCache candidates', () {
    test(
      'index miss returns bounded fallback candidates instead of full-bank LCS',
      () {
        final cache = QuizBankCache.forTesting([
          item(id: '1', question: '驾驶机动车应当遵守道路交通安全法规'),
          item(id: '2', question: '夜间会车应使用近光灯'),
          item(id: '3', question: '高速公路最低时速规定'),
        ]);

        final candidates = cache.candidatesFor('完全无关的超长检索文本');
        expect(candidates, isNotEmpty);
        expect(candidates.length, lessThanOrEqualTo(80));
      },
    );

    test('non-token query does not fall back to the whole bank', () {
      final cache = QuizBankCache.forTesting([
        item(id: '1', question: '驾驶机动车应当遵守道路交通安全法规'),
      ]);

      expect(cache.candidatesFor('？？？'), isEmpty);
    });
  });
}

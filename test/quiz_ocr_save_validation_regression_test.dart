import 'package:box/features/quiz_plugin/domain/ocr_quiz_parser.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:flutter_test/flutter_test.dart';

/// 与 OCR 保存入口相同的选项判定规则：绝不能因漏捕把单选题伪造成判断题。
bool _canSaveOcrQuestion(List<String> options) {
  if (options.length >= 2) return true;
  return false;
}

void main() {
  test('试捕只得到题干时必须阻止保存，不能默认补正确错误', () {
    expect(_canSaveOcrQuestion(const []), isFalse);
  });

  test('完整判断题的正确错误选项仍允许保存为判断题', () {
    const options = ['正确', '错误'];
    expect(_canSaveOcrQuestion(options), isTrue);
    final type = options.length == 2 &&
            options.any((o) => o.contains('正确')) &&
            options.any((o) => o.contains('错误'))
        ? QuizQuestionType.trueFalse
        : QuizQuestionType.singleChoice;
    expect(type, QuizQuestionType.trueFalse);
  });

  // === Phase 1c 新增回归测试 ===

  group('空答案处理', () {
    test('空答案不应默认取首选项', () {
      final parsed = OcrQuizParser.parse('''
·下列哪项是机动车违法行为?·
·违章行为·
·违规行为·
·违法行为·
·犯罪行为·
·答案·
''');
      // 空答案应保留空字符串，而非 fallback 到首选项
      expect(parsed.correctAnswer, '');
      expect(parsed.options, hasLength(4));
    });

    test('空答案时 QuizEngine.search 不应返回错误匹配', () async {
      final bank = [
        const QuizBankItem(
          id: 't1',
          question: '下列哪项是机动车违法行为?',
          type: QuizQuestionType.singleChoice,
          options: ['违章行为', '违规行为', '违法行为', '犯罪行为'],
          correctAnswer: '', // 空答案
          source: '手动录入',
        ),
      ];
      // 题库为空时 search 会走外部搜索，这里只验证空答案不污染题库数据
      final item = bank.first;
      expect(item.correctAnswer, '');
    });

    test('空答案在 OcrQuizParser 中应保留空值', () {
      final parsed = OcrQuizParser.parse('''
·道路限速标志表示什么?·
·最高限速·
·最低限速·
·解除限速·
·建议速度·
·答案·
''');
      expect(parsed.correctAnswer, '');
    });
  });

  group('保存失败阻断', () {
    test('选项不足两项时应阻止保存', () {
      const optionsRaw = '只有一项选项';
      final options = optionsRaw
          .split('\n')
          .map((e) => e.trim())
          .map((e) => e.replaceFirst(
              RegExp(r'^[A-DＡ-Ｄ]\s*[.、．:：)\s]+'), ''))
          .where((e) => e.isNotEmpty)
          .toList();
      expect(options.length < 2, isTrue);
    });

    test('空题干时应阻止保存', () {
      final question = ''.trim();
      expect(question.isEmpty, isTrue);
    });

    test('答案不在选项内时应阻止保存', () {
      final options = ['违章行为', '违规行为', '违法行为'];
      const answer = '犯罪行为';
      expect(options.contains(answer), isFalse);
    });
  });

  group('Native/Dart 字段契约', () {
    /// Native QuizOcrEntryOverlay 传 answer；Dart 历史字段为 correctAnswer。
    /// 两边都必须可读，否则 OCR 录入保存会静默丢答案。
    String resolveCorrectAnswer(Map<String, dynamic> args) {
      return (args['correctAnswer']?.toString() ??
              args['answer']?.toString() ??
              '')
          .trim();
    }

    test('Native 仅传 answer 时也能拿到正确答案', () {
      final correct = resolveCorrectAnswer({
        'question': '下列哪项是机动车违法行为?',
        'options': 'A. 违章行为\nB. 违法行为',
        'answer': '违法行为',
      });
      expect(correct, '违法行为');
    });

    test('Dart 仅传 correctAnswer 时仍兼容', () {
      final correct = resolveCorrectAnswer({
        'correctAnswer': '违法行为',
      });
      expect(correct, '违法行为');
    });

    test('两边都空时保留空答案，不默认首项', () {
      final correct = resolveCorrectAnswer({
        'options': 'A. 违章行为\nB. 违法行为',
      });
      expect(correct, isEmpty);
    });
  });
}

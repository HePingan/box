import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/quiz_plugin/domain/ocr_quiz_parser.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';

/// 新规题标记链路：卷面「新规题」标签 → 解析器 → 题库模型 → DB 往返。
///
/// 真机现象：同题干「货车上高速超过限宽或限高一次记几分」同时存着
/// 新规 1 分和旧规 6 分两条答案，引擎没有任何依据消歧，只能报「请人工确认」。
/// 这些测试锁住新增的标记通道，确保标签不会被解析/落库环节吞掉。
void main() {
  const raw = '新规题 单选\n货车上高速公路行驶超过规定限宽或限高的，一次记几分？\n'
      'A. 6分\nB. 3分\nC. 9分\nD. 1分\n正确答案：D';

  test('OCR 解析器识别卷面「新规题」标签', () {
    final parsed = OcrQuizParser.parse(raw);
    expect(parsed.isNewRule, isTrue);
    expect(parsed.question, contains('货车上高速公路'));
    expect(parsed.options, contains('1分'));
  });

  test('无标签时默认不是新规题', () {
    final parsed = OcrQuizParser.parse(raw.replaceFirst('新规题 ', ''));
    expect(parsed.isNewRule, isFalse);
  });

  test('新规标记随题库模型写入 DB 并完整读回', () {
    final source = OcrQuizParser.parse(raw);
    final item = QuizBankItem(
      id: 'newrule-1',
      question: source.question,
      type: QuizQuestionType.singleChoice,
      options: source.options,
      correctAnswer: '1分',
      source: '录入',
      isNewRule: source.isNewRule,
    );

    final row = item.toDb();
    expect(row['isNewRule'], 1);

    final restored = QuizBankItem.fromDb(row);
    expect(restored.isNewRule, isTrue);
    expect(restored.correctAnswer, '1分');
    expect(restored.options, source.options);
  });

  test('旧库缺少 isNewRule 列时按非新规处理，不误伤存量题', () {
    final row = QuizBankItem(
      id: 'legacy-1',
      question: '旧题',
      type: QuizQuestionType.singleChoice,
      options: const ['甲', '乙'],
      correctAnswer: '甲',
    ).toDb();
    row.remove('isNewRule');

    expect(QuizBankItem.fromDb(row).isNewRule, isFalse);
  });

  test('copyWith 保留新规标记', () {
    final item = QuizBankItem(
      id: 'x',
      question: '题',
      type: QuizQuestionType.singleChoice,
      options: const ['甲', '乙'],
      correctAnswer: '甲',
      isNewRule: true,
    );
    expect(item.copyWith(question: '新题').isNewRule, isTrue);
    expect(item.copyWith(isNewRule: false).isNewRule, isFalse);
  });
}

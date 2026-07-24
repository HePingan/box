import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/ocr_quiz_parser.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';

/// 模拟 quiz_plugin_entry._fillOcrEntryFromRaw 对选项的展示加工
/// （带 A./B. 前缀），确保与 OcrQuizParser 输出一致。
List<String> _toOptionLines(List<String> options) {
  final out = <String>[];
  for (var i = 0; i < options.length; i++) {
    final label = String.fromCharCode(0x41 + (i % 26));
    final o = options[i];
    if (RegExp(r'^[A-D]\s*[.、]').hasMatch(o)) {
      out.add(o);
    } else {
      out.add('$label. $o');
    }
  }
  return out;
}

void main() {
  group('OCR 录入写入题库 == 试捕预览（统一 OcrQuizParser）', () {
    const raw = '''
·x驾驶这种机动车上路行驶属于什么行为?x
·违规行为
·违章行为
·违法行为
·犯罪行为
·答案C
''';

    test('写入题库的数据应是干净的题/选项/答案', () {
      final parsed = OcrQuizParser.parse(raw);
      final optionLines = _toOptionLines(parsed.options);

      expect(parsed.question, '驾驶这种机动车上路行驶属于什么行为?');
      expect(parsed.question, isNot(contains('·')));
      expect(parsed.question, isNot(contains('x')));

      expect(optionLines, [
        'A. 违规行为',
        'B. 违章行为',
        'C. 违法行为',
        'D. 犯罪行为',
      ]);

      // 答案应为选项原文（OcrQuizParser._mapAnswerToOption 已映射）
      expect(parsed.correctAnswer, '违法行为');

      // 关键：不能混入录入窗标题/按钮文案
      final all = [...optionLines, parsed.question, parsed.correctAnswer].join('\n');
      expect(all, isNot(contains('OCR悬浮录入')));
      expect(all, isNot(contains('打开悬浮录入')));
    });

    test('答案 C 能正确映射到选项3', () {
      final parsed = OcrQuizParser.parse(raw);
      expect(parsed.options.indexOf(parsed.correctAnswer), 2);
    });

    test('题库查看复制格式正确', () {
      final parsed = OcrQuizParser.parse(raw);
      final item = QuizBankItem(
        id: 't1',
        question: parsed.question,
        type: QuizQuestionType.singleChoice,
        options: parsed.options,
        correctAnswer: parsed.correctAnswer,
        source: 'OCR录入',
        createdAt: DateTime(2026, 7, 15),
      );
      final copy = _fakeItemToCopy(item);
      expect(copy, contains('【题目】驾驶这种机动车上路行驶属于什么行为?'));
      expect(copy, contains('【选项】'));
      expect(copy, contains('C. 违法行为'));
      expect(copy, contains('【答案】违法行为'));
      expect(copy, isNot(contains('OCR悬浮录入')));
    });
  });
}

/// 复刻 QuizBankViewPage._itemToCopy（避免循环 import 整个页面）
String _fakeItemToCopy(QuizBankItem item) {
  final prefix = ['A', 'B', 'C', 'D', 'E', 'F'];
  final buffer = StringBuffer();
  buffer.writeln('【题目】${item.question}');
  if (item.options.isNotEmpty) {
    buffer.writeln('【选项】');
    for (var i = 0; i < item.options.length; i++) {
      final p = i < prefix.length ? prefix[i] : '${i + 1}';
      final mark = item.options[i] == item.correctAnswer ? '  ✓' : '';
      buffer.writeln('$p. ${item.options[i]}$mark');
    }
  }
  buffer.writeln('【答案】${item.correctAnswer}');
  return buffer.toString().trimRight();
}

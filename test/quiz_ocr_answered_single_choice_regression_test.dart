import 'package:box/features/quiz_plugin/domain/ocr_quiz_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('多选题已答完时，结果区答案 C 与技巧文本不能污染录入选项或变成判断题', () {
    const raw = '''
答题
背题
视频
设置
单选
驾驶电动汽车，图中指示灯亮起表示（）。
读题
A 低荷电状态警告
B 正在充电
C 充电系统故障
D 动力蓄电池故障
答案 C
速记
本题技巧
单个电池闪红色，表示动力蓄电池故障
查看完整技巧
收藏
50/2213
''';

    final parsed = OcrQuizParser.parse(raw);

    expect(parsed.question, '驾驶电动汽车，图中指示灯亮起表示（）。');
    expect(parsed.questionType, 'single_choice');
    expect(parsed.options, const ['低荷电状态警告', '正在充电', '充电系统故障', '动力蓄电池故障']);
    expect(parsed.correctAnswer, '充电系统故障');
    expect(parsed.analysis, contains('单个电池闪红色'));
  });
}

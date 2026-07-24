import 'package:box/features/quiz_plugin/domain/ocr_quiz_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('无字母节点的仪表图标单选题按表示句式提取四项，不能退化为正确错误', () {
    const raw = '''
单选
驾驶电动汽车，图中指示灯亮起表示（ ）。
低荷电状态警告
正在充电
充电系统故障
动力蓄电池故障
答案 C
速记
本题技巧
单个电池闪红色，表示充电系统故障
正确
错误
''';

    final parsed = OcrQuizParser.parse(raw);

    expect(parsed.question, '驾驶电动汽车，图中指示灯亮起表示（ ）。');
    expect(parsed.questionType, 'single_choice');
    expect(parsed.options, const ['低荷电状态警告', '正在充电', '充电系统故障', '动力蓄电池故障']);
    expect(parsed.correctAnswer, '充电系统故障');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/ocr_quiz_parser.dart';

void main() {
  group('OcrQuizParser 驾考无字母选项', () {
    test('题干+4个无前缀短选项（含噪点·×）', () {
      const raw = '''
·设置
·×驾驶这种机动车上路行驶属于什么行为?×
·违规行为
·违章行为
·违法行为
·犯罪行为
''';
      final r = OcrQuizParser.parse(raw);
      expect(r.question, contains('驾驶这种机动车上路行驶属于什么行为'));
      expect(r.question, isNot(contains('·')));
      expect(r.question, isNot(contains('×')));
      expect(r.options, hasLength(4));
      expect(r.options, contains('违规行为'));
      expect(r.options, contains('违章行为'));
      expect(r.options, contains('违法行为'));
      expect(r.options, contains('犯罪行为'));
      expect(r.questionType, 'single_choice');
    });

    test('传统 A. 选项仍正常', () {
      const raw = '''
驾驶机动车在道路上违反交通安全法规的行为属于什么？
A. 违规行为
B. 违章行为
C. 违法行为
D. 犯罪行为
答案：C
''';
      final r = OcrQuizParser.parse(raw);
      expect(r.options, hasLength(4));
      expect(r.correctAnswer, '违法行为');
    });

    test('判断题 A正确 B错误', () {
      const raw = '''
这种标线表示禁止长时停车。
A 正确
B 错误
''';
      final r = OcrQuizParser.parse(raw);
      expect(r.questionType, 'true_false');
      expect(r.options, contains('正确'));
      expect(r.options, contains('错误'));
    });

    test('图片题：·分隔+无字母前缀+选项黏行+末尾答案（真实试捕样本）', () {
      // 悬浮窗试捕预览原文：选项无 A/B/C/D（字母是图形圆圈），
      // 「·」当逻辑项分隔符，且「未立即排除故障」「未将车停到路边」黏成一行。
      const raw = '·x图中故障车辆的违法行为是()。\n'
          '·未设置警告标志·未立即排除故障未将车停到路边\n'
          '·未开启危险报警闪光灯·答案A';
      final r = OcrQuizParser.parse(raw);
      expect(r.question, contains('图中故障车辆的违法行为是'));
      expect(r.question, isNot(contains('·')));
      expect(r.options, hasLength(4));
      expect(r.options, contains('未设置警告标志'));
      expect(r.options, contains('未立即排除故障'));
      expect(r.options, contains('未将车停到路边'));
      expect(r.options, contains('未开启危险报警闪光灯'));
      // 答案 A → 第 0 个选项
      expect(r.correctAnswer, '未设置警告标志');
      expect(r.questionType, 'single_choice');
    });

    test('答案与解析被 OCR 合并为同一行时应分割', () {
      const raw = '''
夜间通过没有交通信号灯的路口应如何操作？
A. 加速通过
B. 减速观察
C. 鸣笛通过
D. 停车等待
答案：B 解析：夜间视线差，应减速观察。
''';
      final r = OcrQuizParser.parse(raw);
      expect(r.correctAnswer, '减速观察');
      expect(r.analysis, contains('夜间视线差'));
      expect(r.correctAnswer, isNot(contains('解析')));
    });
  });
}

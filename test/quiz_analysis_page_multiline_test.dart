import 'package:box/features/quiz_plugin/domain/ocr_quiz_parser.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 红灯回归 #3：解析页「多行」形态（真机 1.18.10 (233) 报告复现）。
///
/// 用户 2026-09-12T21:58 的 233 报告里，下面这些帧仍被拿去检索：
///   PARSE parsed rawLines=5 lines=3 qLen=0 opts=0 q=""
///   PARSE 题干为空 text="本题技巧 红三角是危险报警闪光灯，人为. - 试题详解 有问题"
///   RESULT engine.search 发起 fp=红三角是危险报警闪光灯，人为.   ← 仍在发假题干
///
/// 我在 1.18.10 加的 `hasNoQuestionCandidate` 门**没拦住**：它逐行判断，
/// 而 `红三角是危险报警闪光灯，人为.` 是**解析正文**（不是关键词 chrome），
/// 于是被判为「还有候选」，兜底又把它取成了搜索键。
///
/// 真根因：`本题技巧` 之后的所有内容都是**解析正文**，不可能是题干。
/// 解析器自己已用 `inAnalysis` 表达这个语义，但兜底/门控没有复用。
void main() {
  const analysisFrame = '本题技巧\n'
      '红三角是危险报警闪光灯，人为.\n'
      '- 试题详解\n'
      '有问题';

  group('解析页多行帧：不得产出搜索键', () {
    test('hasNoQuestionCandidate 必须为 true（本题技巧之后全是解析正文）', () {
      expect(OcrQuizParser.hasNoQuestionCandidate(analysisFrame), isTrue,
          reason: '本题技巧之后的内容是解析正文，不构成题干候选');
    });

    test('questionFingerprint 必须为空串（不得拿解析正文去搜）', () {
      expect(QuizPluginEntry.questionFingerprint(analysisFrame), '',
          reason: '真机日志里这里产出了 fp=红三角是危险报警闪光灯，人为.');
    });

    test('真实报告里的解析正文变体同样不得成为搜索键', () {
      const variants = [
        '本题技巧\n无伤亡无争议，拍照撤离防拥堵。\n- 试题详解\n有问题\n视频讲解',
        '本题技巧\n号牌相关：假证假牌12分，遮.\n- 试题详解\n有问题\n视频讲解',
        '本题技巧\n违标违线、违规用灯、未按时年.\n- 试题详解\n有问题\n视频讲解',
        '本题技巧\n红三角是危险报警闪光灯，人为.\n- 试题详解\n有问题',
      ];
      for (final v in variants) {
        expect(QuizPluginEntry.questionFingerprint(v), '',
            reason: '解析页帧不得产出搜索键: $v');
      }
    });
  });

  group('不得回归：真正的题目仍要正常产出搜索键', () {
    test('完整判断题（题干+选项）', () {
      const good = '发生仅有轻微财产损失的事故可以适用简易处理程序，但有交通肇事、危险驾驶犯罪嫌疑的除外。\n'
          'A. 正确\nB. 错误';
      expect(
        QuizPluginEntry.questionFingerprint(good),
        '发生仅有轻微财产损失的事故可以适用简易处理程序，但有交通肇事、危险驾驶犯罪嫌疑的除外。',
      );
    });

    test('题干里出现「技巧」二字但整体是题干，不得误杀', () {
      const good = '驾驶机动车在道路上行驶时，正确使用灯光的技巧是什么？\n'
          'A. 提前开启转向灯\nB. 随意使用远光灯';
      final fp = QuizPluginEntry.questionFingerprint(good);
      expect(fp, isNotEmpty, reason: '含「技巧」的真题干不得被误判为解析页');
      expect(fp.contains('灯光'), isTrue);
    });

    test('题干以「本题」开头但不是解析标记，不得误杀', () {
      const good = '本题答案正确的是哪一项？\nA. 减速慢行\nB. 加速通过';
      expect(QuizPluginEntry.questionFingerprint(good), isNotEmpty);
    });
  });
}

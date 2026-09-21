import 'package:box/features/quiz_plugin/domain/ocr_quiz_parser.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 红灯回归 #4：首页/答题页的**进度条文案**被当成题干去搜。
///
/// 真机 1.18.10 (233) 报告（2026-09-12T21:57:35）：
///   PARSE parsed rawLines=3 lines=2 qLen=17 opts=0 q="做题进度 41/100题 继续答题"
///   RESULT engine.search 发起 fp=做题进度41/100题继续答题
///   RESULT engine.search 返回 ok=false →「无结果：引擎未命中，悬浮窗停在检索中」
///
/// `做题进度 X/Y题 继续答题` 是**答题页/首页的 UI 文案**，不可能是题干。
/// 与解析页帧同类：仍属「整帧没有题干候选」。
void main() {
  group('进度条帧：不得产出搜索键', () {
    test('做题进度 X/Y题 继续答题', () {
      const f = '做题进度 41/100题 继续答题';
      expect(OcrQuizParser.hasNoQuestionCandidate(f), isTrue);
      expect(QuizPluginEntry.questionFingerprint(f), '',
          reason: '真机日志里这里产出了 fp=做题进度41/100题继续答题');
    });

    test('多种进度/继续答题文案变体', () {
      const variants = [
        '做题进度 21/100题 继续答题',
        '做题进度 100/100题 继续答题',
        '做题进度 7/50题 继续答题',
        '继续答题',
      ];
      for (final v in variants) {
        expect(QuizPluginEntry.questionFingerprint(v), '',
            reason: '进度条文案不得成为搜索键: $v');
      }
    });

    test('多行帧里夹着进度条，仍应整体判为无候选', () {
      const f = '做题进度 41/100题 继续答题\n单选\n收藏';
      expect(QuizPluginEntry.questionFingerprint(f), '');
    });
  });

  group('不得回归：含「进度」「答题」字样的真题干不得误杀', () {
    test('题干里出现「答题」二字', () {
      const good = '驾驶机动车在高速公路上行驶，答题时应注意以下哪项？\nA. 保持车距\nB. 随意变道';
      final fp = QuizPluginEntry.questionFingerprint(good);
      expect(fp, isNotEmpty, reason: '含「答题」的真题干不得被误判为进度条');
    });

    test('题干里出现「进度」二字', () {
      const good = '关于施工进度与道路通行，下列说法正确的是？\nA. 施工进度不影响通行\nB. 应当减速慢行';
      expect(QuizPluginEntry.questionFingerprint(good), isNotEmpty);
    });

    test('正常题干仍正常', () {
      const good = '发生仅有轻微财产损失的事故可以适用简易处理程序，但有交通肇事、危险驾驶犯罪嫌疑的除外。\nA. 正确\nB. 错误';
      expect(QuizPluginEntry.questionFingerprint(good),
          '发生仅有轻微财产损失的事故可以适用简易处理程序，但有交通肇事、危险驾驶犯罪嫌疑的除外。');
    });
  });
}

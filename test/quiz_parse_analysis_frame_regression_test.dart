import 'package:box/features/quiz_plugin/domain/ocr_quiz_parser.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 红灯回归：真机 1.18.9 (232) 日志暴露的真根因（2026-09-12T21:19:20~21:19:28）。
///
/// 用户已确认：「本题技巧/试题详解」是**答完题后跳转到的解析页**，
/// 采集在答完题这一动作触发的帧上抓图 → 屏幕上根本没有题干。
///
/// 日志铁证：
///   PARSE parsed rawLines=6 lines=4 qLen=0 opts=0 answer=(空) q=""   ← 解析器判空，正确
///   PARSE 题干为空 text="本题技巧 无伤亡无争议，拍照撤离防拥堵。 - 试题详解 ..."
///   THROTTLE recordAttempt stmt=本题技巧                              ← 兜底硬凑的假题干
///   RESULT engine.search 发起 fp=本题技巧                             ← 拿假题干去搜，必然不中
///
/// 本文件锁定两件事：
///   A. 解析页帧不得产出假题干（本题技巧/视频讲解/相关问题…）
///   B. 兜底逻辑不得把解析页区块标记当搜索键
///
/// 注意：「本题技巧」之后的内容在真实解析页上**就是解析正文**，
/// 解析器会（正确地）把其后各行归入 analysis 并 continue，
/// 因此不得构造「本题技巧后紧跟题干」这种真实世界不存在的用例。
void main() {
  String stem(String raw) => QuizPluginEntry.questionFingerprint(raw);

  group('A. 解析页帧不得产出假题干', () {
    test('纯解析页 → 题干为空', () {
      const frame = '本题技巧\n'
          '无伤亡无争议，拍照撤离防拥堵。\n'
          '- 试题详解\n'
          '有问题\n'
          '视频讲解';
      expect(OcrQuizParser.parse(frame).question, isEmpty);
    });

    test('带时长噪声的解析页 → 题干为空', () {
      const frame = '本题技巧\n'
          '违标违线、违规用灯、未按时年. - 试题详解 有问题 视频讲解';
      expect(OcrQuizParser.parse(frame).question, isEmpty);
    });

    test('「视频讲解」「相关问题」不得被当成题干', () {
      for (final marker in const ['视频讲解', '相关问题', '试题详解', '本题口诀']) {
        final frame = '$marker\n随便一句解析内容。';
        expect(OcrQuizParser.parse(frame).question, isNot(marker),
            reason: '「$marker」是页面区块标记，不是题干');
      }
    });
  });

  group('B. 兜底：解析页标记不得成为搜索键（本轮真根因）', () {
    test('「本题技巧」不得成为搜索键', () {
      const frame = '本题技巧\n无伤亡无争议，拍照撤离防拥堵。 - 试题详解 有问题 视频讲解';
      expect(stem(frame), isNot('本题技巧'),
          reason: '日志 fp=本题技巧 就是这么来的');
    });

    test('各种解析页标记都不得成为搜索键', () {
      for (final marker in const [
        '本题技巧',
        '试题详解',
        '视频讲解',
        '本题口诀',
        '相关问题',
      ]) {
        expect(stem('$marker\n随便一句解析内容。'), isNot(marker),
            reason: '「$marker」是页面区块标记，不是题干');
      }
    });

    test('解析页帧应产出空搜索键（宁可不搜，也不要拿假题干去搜）', () {
      const frame = '本题技巧\n无伤亡无争议，拍照撤离防拥堵。 - 试题详解 有问题 视频讲解';
      expect(stem(frame), isEmpty,
          reason: '无题干时应放弃本次检索，而不是用「本题技巧」污染搜索与节流状态');
    });

    test('不得回归：真正的题干仍要能正常产出', () {
      const frame = '公路客运车辆载客超过额定乘员20%的，应处200元以上500元以下的罚款，并扣留机动车至违法状态消除。\n'
          'A. 正确\nB. 错误';
      final s = stem(frame);
      expect(s, contains('公路客运车辆载客超过额定乘员'));
      expect(s, isNotEmpty);
    });

    test('不得回归：日志里真正命中的那题，指纹必须正常', () {
      // 21:19:22.241 MATCH HIT score=1.0 qid=quiz_00642b71c901 对应的题干
      const frame = '公路客运车辆载客超过额定乘员20%的，应处200元以上500元以下的罚款，并扣留机动车至违法状态消除。';
      expect(stem(frame), contains('公路客运车辆载客超过额定乘员'));
    });
  });
}

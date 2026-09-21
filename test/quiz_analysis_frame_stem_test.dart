import 'package:box/features/quiz_plugin/domain/ocr_quiz_parser.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 红灯回归：真机 1.18.9 (232) 日志（2026-09-12T21:19:20~21:19:28）。
///
/// 用户已确认：「本题技巧/试题详解」是**答完题后跳转到的解析页**，
/// 采集在这一帧抓图 → 屏幕上根本没有题干。
///
/// 日志铁证：
///   PARSE parsed rawLines=6 lines=4 qLen=0 opts=0 answer=(空) q=""       ← 解析器判空，正确
///   PARSE 题干为空 text="本题技巧 无伤亡无争议，拍照撤离防拥堵。 - 试题详解 ..."
///   随后 THROTTLE recordAttempt stmt=本题技巧                            ← 兜底硬凑出的假题干
///   RESULT engine.search 发起 fp=本题技巧                                ← 拿假题干去搜，必然不中
///
/// 本文件锁定两件事：
///   A. 解析器对「纯解析页帧」必须判空题干（现状已正确，防回归）
///   B. **兜底逻辑不得把解析页区块标记（本题技巧/试题详解/视频讲解…）
///      当成题干** —— 这才是日志里 fp=本题技巧 的来源，也是本轮真根因。
void main() {
  /// 直接调用**真实实现**（QuizPluginEntry.questionFingerprint），
  /// 不再复制等价逻辑，确保测的就是线上跑的那份。
  String fallbackStem(String raw) => QuizPluginEntry.questionFingerprint(raw);

  group('A. 解析器：解析页帧判空题干（现状正确，防回归）', () {
    test('纯解析页 → 题干为空', () {
      const frame = '本题技巧\n'
          '无伤亡无争议，拍照撤离防拥堵。\n'
          '- 试题详解\n'
          '有问题\n'
          '视频讲解';
      expect(OcrQuizParser.parse(frame).question, isEmpty);
    });

    test('带时长噪声的解析页 → 题干仍为空', () {
      const frame = '本题技巧\n'
          '违标违线、违规用灯、未按时年. - 试题详解 有问题 视频讲解';
      expect(OcrQuizParser.parse(frame).question, isEmpty);
    });
  });

  group('B. 兜底：不得把解析页标记当题干（本轮真根因）', () {
    test('「本题技巧」不得成为搜索键', () {
      const frame = '本题技巧\n无伤亡无争议，拍照撤离防拥堵。 - 试题详解 有问题 视频讲解';
      expect(fallbackStem(frame), isNot('本题技巧'),
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
        final frame = '$marker\n随便一句解析内容。';
        final stem = fallbackStem(frame);
        expect(stem, isNot(marker), reason: '「$marker」是页面区块标记，不是题干');
      }
    });

    test('解析页帧应产出空搜索键（宁可不搜，也不要拿假题干去搜）', () {
      const frame = '本题技巧\n无伤亡无争议，拍照撤离防拥堵。 - 试题详解 有问题 视频讲解';
      expect(fallbackStem(frame), isEmpty,
          reason: '无题干时应放弃本次检索，而不是用「本题技巧」污染搜索与节流状态');
    });

    test('不得回归：真正的题干仍要能正常产出', () {
      const frame = '公路客运车辆载客超过额定乘员20%的，应处200元以上500元以下的罚款，并扣留机动车至违法状态消除。\n'
          'A. 正确\nB. 错误';
      final stem = fallbackStem(frame);
      expect(stem, contains('公路客运车辆载客超过额定乘员'));
      expect(stem, isNotEmpty);
    });
  });
}

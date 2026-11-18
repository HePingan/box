// 「识别成功但屏幕报未搜到」根因回归（2026-11-18 真机截图实证）。
//
// 报障现场（截图 img_8093e789）：过程区写着
//   ① 读屏截图332KB → 压缩至148KB
//   ② 提交模型(代理档，实际由后台指定)
//   ③ 第1次请求(预算44s)
//   ④ 识别成功，用时3276ms
// 而结论区写的是「未搜到答案。点右上角紫色 AI 按钮，用 AI 联网搜题。」徽章「未命中」。
//
// 真因：读屏要跑 3~15 秒，跑完那一刻又抓了一屏 ⇒ generation 变了 ⇒
// `_runVisionFallback` 里那句 **严格的** `_isCurrentRequest(...) return null`
// 把**已经拿到的答案**丢掉，调用方随即走 `_pushMiss` 报未命中。
// 于是同一块悬浮窗上同时写着「识别成功」和「未搜到」。
//
// 修法两条（这个文件钉死它们）：
//   ① 判据与 `_acceptVisionResult` 统一：只认纯题干，同题答案不许被 generation 漂移否掉；
//   ② 真的换题了才丢，并且记下「本题读屏其实成功过」—— 调用方不许再补一句「未搜到」。
import 'dart:io';

import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(QuizPluginEntry.debugResetVisionState);

  group('「读屏成功但被丢弃」标记', () {
    test('同题 → 命中一次即消费（避免把后续真实的未命中一起吞掉）', () {
      QuizPluginEntry.debugSetDiscardedVisionStem('这个标志是何含义');
      expect(QuizPluginEntry.debugConsumeDiscardedVision('这个标志是何含义'), isTrue);
      expect(QuizPluginEntry.debugConsumeDiscardedVision('这个标志是何含义'), isFalse,
          reason: '标记必须一次性消费，否则后续真实未命中永远不出来');
    });

    test('带切题后缀的指纹也算同题（|image:<dHash> 只属于切题身份）', () {
      QuizPluginEntry.debugSetDiscardedVisionStem('这个标志是何含义');
      expect(
        QuizPluginEntry.debugConsumeDiscardedVision(
            '这个标志是何含义|image:0123456789abcdef'),
        isTrue,
      );
    });

    test('换题 → 不消费、不影响新题', () {
      QuizPluginEntry.debugSetDiscardedVisionStem('这个标志是何含义');
      expect(QuizPluginEntry.debugConsumeDiscardedVision('驾驶机动车逆行记几分'), isFalse);
      // 旧标记仍在，等它自己的题来消费
      expect(QuizPluginEntry.debugConsumeDiscardedVision('这个标志是何含义'), isTrue);
    });

    test('没标记时永远不拦', () {
      expect(QuizPluginEntry.debugConsumeDiscardedVision('任意题目'), isFalse);
    });

    test('reset 清干净', () {
      QuizPluginEntry.debugSetDiscardedVisionStem('这个标志是何含义');
      QuizPluginEntry.debugResetVisionState();
      expect(QuizPluginEntry.debugConsumeDiscardedVision('这个标志是何含义'), isFalse);
    });
  });

  group('源码契约：读屏拿到答案后不得用严格 generation 丢弃', () {
    final dart = File(
      'lib/features/quiz_plugin/presentation/quiz_plugin_entry.dart',
    ).readAsStringSync();

    test('searchVisionApi 之后紧跟的是宽容判据 _acceptVisionResult', () {
      final i = dart.indexOf('await engine.searchVisionApi(');
      expect(i, greaterThan(0));
      final tail = dart.substring(i, i + 2200);
      expect(tail.contains('_acceptVisionResult(requestGeneration, requestFingerprint)'),
          isTrue,
          reason: '这里曾经是裸 _isCurrentRequest → 同题答案被 generation 漂移丢掉');
      expect(
        tail.contains('if (!_isCurrentRequest(requestGeneration, requestFingerprint)) return null;'),
        isFalse,
        reason: '严格判据不许再出现在读屏已出结果之后',
      );
    });

    test('丢弃时要记下「本题读屏成功过」', () {
      expect(dart.contains('_discardedVisionStem ='), isTrue);
      expect(dart.contains('不报未命中：本题读屏已成功，结果因换题丢弃'), isTrue);
    });
  });
}

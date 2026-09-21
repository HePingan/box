import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/quiz_plugin/domain/quiz_search_policy.dart';

/// 「回滑就识别不出来」回归测试（真机 1.18.15 (238) 录屏，2026-09-13 11:55）。
///
/// 复现现象：用户在题目列表里**回滑**（从当前题滑回上一题）后，悬浮窗仍显示
/// **后一题**的答案，没有换成回滑后所在题的答案 —— 即"回滑就识别不出来"。
///
/// 录屏实证（回滑时刻的画面）：
///   屏幕题干 = 图中地面标记表示（ ）。        正确答案 = 人行横道预告
///   悬浮窗显示 = 向侧滑的反方向转动方向盘适量修正 ← 这是**后一题**（泥泞路侧滑）的答案
///   → 题干与悬浮窗答案属于两道不同的题，说明回滑后悬浮窗没有被刷新。
///
/// 根因：`_handleCapturedQuestion` 里 `shouldSuppress` 返回 true 时**直接 return**，
/// 跳过了 `_showNewQuestionSearching` / 答案重绘。回滑到一道**曾经命中并已锁定**
/// 的题时（同题干同选项同图），节流把这次捕获当成"完全重复"拦掉，
/// 而此刻悬浮窗里装的却是别的题的答案 —— 于是永远停在错答案上。
///
/// 关键区分：**节流该拦的是"重复检索"（省算力），不该拦"重绘"（纠正画面）。**
/// 同一道题在屏幕上重新出现，即使不用重新检索题库，也必须把它的答案重新渲染一遍。
void main() {
  const stem = '图中地面标记表示（ ）';
  const options = ['人行横道预告', '交叉路口预告', '减速让行预告', '停车让行预告'];

  test('回滑到已锁定题：同题同选项不得拦截重绘（否则悬浮窗停在别题答案）', () {
    final policy = QuizSearchPolicy();
    // 回滑前：这道题曾命中并锁定
    policy.recordSuccess(
      stem: stem,
      options: options,
      source: QuizResultSource.localBank,
      questionScore: 100,
      optionScore: 100,
    );

    // 用户回滑，这一题重新出现在屏幕上 —— 节流可以跳过"重新检索"，
    // 但调用方必须知道需要"重绘"，否则悬浮窗继续显示后一题的答案。
    final suppressed = policy.shouldSuppress(stem: stem, options: options);

    expect(
      suppressed,
      isTrue,
      reason: '同题同选项的重复捕获确实应跳过检索（省算力）',
    );

    // 但"跳过检索"不等于"跳过重绘"。策略必须能告诉调用方：
    // 这一题有已知答案、且当前画面可能与答案不一致 → 需要把答案重新渲染。
    expect(
      policy.shouldRedrawOnRecapture(stem: stem, options: options),
      isTrue,
      reason: '回滑到已锁定题时，即使跳过检索也必须重绘该题答案，'
          '否则悬浮窗会停在上一题的答案上（"回滑就识别不出来"）',
    );
  });

  test('非同题回滑：换成另一道曾锁定的题，同样要求重绘', () {
    final policy = QuizSearchPolicy();
    const otherStem = '车辆在泥泞路上前轮发生侧滑时，以下做法正确的是？';
    const otherOptions = ['向侧滑的反方向转动转向盘适量修正'];

    policy.recordSuccess(
      stem: otherStem,
      options: otherOptions,
      source: QuizResultSource.localBank,
      questionScore: 100,
      optionScore: 100,
    );

    // 当前屏幕上的是「图中地面标记」，与锁定的「泥泞路侧滑」不同题
    expect(
      policy.shouldSuppress(stem: stem, options: options),
      isFalse,
      reason: '题目不同，绝不能拦截检索',
    );
    // 非同题本就走完整检索路径，重绘自然发生
    expect(
      policy.shouldRedrawOnRecapture(stem: stem, options: options),
      isFalse,
      reason: '非同题由正常检索路径负责刷新，无需额外重绘信号',
    );
  });

  test('首次遇到该题（未命中过）：不拦截、也不需要重绘信号', () {
    final policy = QuizSearchPolicy();
    expect(
      policy.shouldSuppress(stem: stem, options: options),
      isFalse,
      reason: '没有成功结果时绝不拦首次检索',
    );
    expect(
      policy.shouldRedrawOnRecapture(stem: stem, options: options),
      isFalse,
      reason: '没有已知答案就无需重绘',
    );
  });
}

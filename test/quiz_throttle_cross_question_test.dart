import 'package:box/features/quiz_plugin/domain/quiz_search_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// 红灯回归 #2：跨题残留的 attempt 状态必须作废。
///
/// 真机 1.18.9 (232) 日志（2026-09-12T21:19:22.990）：
///   THROTTLE 指纹不匹配：attempt=51 now=4
///
/// 51 = 上一题（已命中 localBank）的指纹长度
///  4 = 本题（解析页噪声「本题技巧」）的指纹长度
///
/// 根因：`shouldSuppressThrottled` 在 `recordAttempt` **之前**被调用
/// （quiz_plugin_entry.dart:697 vs :703），于是它拿「上一题的 _attemptStem」
/// 去比「本题的 normalizedStem」，跨题必然不等 → 节流静默失效。
///
/// 修复语义：检测到换题时，把上一题的 attempt/success 状态作废。
/// 不降阈值、不改 success 语义。
void main() {
  const q1 = '公路客运车辆载客超过额定乘员20%的，应处200元以上500元以下的罚款，并扣留机动车至违法状态消除。';
  const q2 = '本题技巧';

  test('上一题成功后，跨到新题：节流状态必须作废（不得残留）', () {
    final p = QuizSearchPolicy();
    // 上一题：attempt → success（命中 localBank，可节流）
    p.recordAttempt(stem: q1, options: const ['正确', '错误']);
    p.recordSuccess(
      stem: q1,
      options: const ['正确', '错误'],
      source: QuizResultSource.localBank,
      questionScore: 100,
      optionScore: 100,
    );
    // 上一题窗口内重复 → 应被节流
    expect(
      p.shouldSuppressThrottled(stem: q1, options: const ['正确', '错误']),
      isTrue,
      reason: '同一题的窗口内完全重复应被节流',
    );

    // 换到新题：不得沿用上一题的 success 状态
    final suppressedForNewQuestion =
        p.shouldSuppressThrottled(stem: q2, options: const []);
    expect(suppressedForNewQuestion, isFalse,
        reason: '换题后必须放行检索；正是这里静默失效导致每题重复全量检索');

    // 且状态已作废：新题此时不应被当作「已成功」
    expect(
      p.shouldSuppressThrottled(stem: q2, options: const []),
      isFalse,
      reason: '作废后连续调用仍不得节流（未产出成功结果前不应节流）',
    );
  });

  test('不得回归：同题重复仍要能节流（修 A 不得伤 B）', () {
    final p = QuizSearchPolicy();
    p.recordAttempt(stem: q1, options: const ['正确', '错误']);
    p.recordSuccess(
      stem: q1,
      options: const ['正确', '错误'],
      source: QuizResultSource.localBank,
      questionScore: 100,
      optionScore: 100,
    );
    expect(p.shouldSuppressThrottled(stem: q1, options: const ['正确', '错误']),
        isTrue);
    expect(p.shouldSuppressThrottled(stem: q1, options: const ['正确', '错误']),
        isTrue, reason: '同题节流在多次调用后仍须稳定生效');
  });

  test('已知行为（非本轮修改）：低置信结果也会置 attemptSucceeded', () {
    // 事实：recordSuccess 内部 **无条件** `_attemptSucceeded = true`
    //   （quiz_search_policy.dart:121），与 questionScore/是否 reliable 无关；
    //   只有 _lockedStem 才受 isReliableLocal 控制。
    // 因此低置信结果同样会让窗口内的完全重复被节流。
    //
    // 这不是本轮引入的，也不是本轮要改的（改动它会改变节流语义，属 B 档，
    // 需拍板）。这里把现状**钉住**，避免将来误以为是回归。
    final p = QuizSearchPolicy();
    p.recordAttempt(stem: q1, options: const ['A', 'B']);
    p.recordSuccess(
      stem: q1,
      options: const ['A', 'B'],
      source: QuizResultSource.localBank,
      questionScore: 60, // < 95，低置信
      optionScore: 60,
    );
    expect(p.shouldSuppressThrottled(stem: q1, options: const ['A', 'B']),
        isTrue,
        reason: '现状：attemptSucceeded 与置信度无关；若这条变了说明有人改了语义');
  });
}

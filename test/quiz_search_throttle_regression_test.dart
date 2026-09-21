import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_search_policy.dart';

/// 回归（2026-09-12 用户报障）：
/// 「改了后之前能秒出的题现在也出不来了，这是什么原因？更糟糕了？」
///
/// 复现真实序列（用户实际操作）：
///   1. 题A 首次捕获 → 检索成功 → 显示答案（此前这里就是秒出）
///   2. 题库/页面继续推进，同一题的**第二次捕获**到来
///      （无障碍 repeat、OCR 兜底、试捕 attempt+1、页面内容渐进加载）
///   3. 老代码：3 秒窗口内同题 → 拦截（这是「防滚动刷屏」的本意）
///      新代码：recordAttempt 无条件把 _attemptSucceeded 置 false，
///             于是「同题第二次」也被判为未成功 → 放行 → 又一次全量检索。
void main() {
  const stem = '驾驶机动车不按规定使用灯光的，一次记3分。';
  const options = ['正确', '错误'];

  QuizSearchPolicy buildPolicy() => QuizSearchPolicy();

  group('节流不得让「能秒出的题」变慢或失效', () {
    test('已成功后，同题第二次捕获必须被节流（不得重复全量检索）', () {
      final p = buildPolicy();
      // 第一次：发起 + 成功
      p.recordAttempt(stem: stem, options: options);
      p.recordSuccess(
        stem: stem,
        options: options,
        source: QuizResultSource.localBank,
        questionScore: 100,
        optionScore: 100,
      );

      // 第二次同题捕获（模拟 repeat / OCR 兜底），应被节流
      expect(
        p.shouldSuppressThrottled(stem: stem, options: options),
        isTrue,
        reason: '同题在节流窗内的重复捕获必须被拦下，否则每题都会被重复检索，'
            '原本秒出的题会因为重复全量检索而变卡甚至答不出',
      );
    });

    test('recordAttempt 不得抹掉「已成功」状态（核心缺陷）', () {
      final p = buildPolicy();
      p.recordAttempt(stem: stem, options: options);
      p.recordSuccess(
        stem: stem,
        options: options,
        source: QuizResultSource.localBank,
        questionScore: 100,
        optionScore: 100,
      );
      // 真实调用顺序问题：_handleCapturedQuestion 里同题第二次会再走一次
      // recordAttempt（因为它无条件在检索前记账），此时必须**保留**成功状态。
      p.recordAttempt(stem: stem, options: options);
      expect(
        p.shouldSuppressThrottled(stem: stem, options: options),
        isTrue,
        reason: 'recordAttempt 无条件把 _attemptSucceeded 清成 false，'
            '导致已经成功过的同题重复请求全部放行 —— 这就是'
            '「改了后之前能秒出的题现在也出不来」的直接原因',
      );
    });

    test('首次失败仍必须放行重试（上一轮修复不能被推翻）', () {
      final p = buildPolicy();
      p.recordAttempt(stem: stem, options: options);
      // 未成功 → 必须放行
      expect(p.shouldSuppressThrottled(stem: stem, options: options), isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_search_policy.dart';

/// 第二轮：验证真机上「秒出的题变慢」
///
/// 场景：题A 秒出答案 → 用户没动，页面/无障碍每 240ms 重复推送同一题
/// 期望：只有第一次真正检索，后续全部被节流。
/// 若节流失效，每题都会重新全量查库 + 走外部 API，表现为「变慢/出不来」。
void main() {
  const stem = '机动车在道路上发生故障，需要停车排除故障时，驾驶人应当怎么做？';
  const options = ['开启危险报警闪光灯', '将车辆移至不妨碍交通的地方停放'];

  test('同题连续 5 次捕获：只应放行 1 次', () {
    final p = QuizSearchPolicy();
    var allowed = 0;
    var now = DateTime(2026, 9, 12, 19, 30);
    p.clock = () => now;

    for (var i = 0; i < 5; i++) {
      if (!p.shouldSuppressThrottled(stem: stem, options: options)) {
        allowed++;
        p.recordAttempt(stem: stem, options: options);
        // 每次捕获都成功命中本地题库
        p.recordSuccess(
          stem: stem,
          options: options,
          source: QuizResultSource.localBank,
          questionScore: 100,
          optionScore: 100,
        );
      }
      now = now.add(const Duration(milliseconds: 240));
    }

    expect(
      allowed,
      1,
      reason: '240ms 间隔的 5 次同题捕获只应产生 1 次真实检索；'
          'allowed=$allowed 说明节流失效，每题被重复全量检索 → 「变慢/出不来」',
    );
  });

  test('翻到新题再翻回：必须允许重新检索（不能被节流锁死）', () {
    final p = QuizSearchPolicy();
    var now = DateTime(2026, 9, 12, 19, 30);
    p.clock = () => now;

    // 题A 成功
    p.recordAttempt(stem: stem, options: options);
    p.recordSuccess(
      stem: stem,
      options: options,
      source: QuizResultSource.localBank,
      questionScore: 100,
      optionScore: 100,
    );
    // 翻到题B
    now = now.add(const Duration(seconds: 1));
    p.recordAttempt(stem: '题B的题干内容', options: const ['甲', '乙']);
    // 立刻翻回题A（题B 还没成功）
    expect(
      p.shouldSuppressThrottled(stem: stem, options: options),
      isFalse,
      reason: '换题后 _attemptStem 已改为题B，翻回题A 应放行重新检索',
    );
  });
}

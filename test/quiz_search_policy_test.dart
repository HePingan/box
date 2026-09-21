import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_search_policy.dart';

void main() {
  test('低质量半题命中不锁定，选项补全后允许纠错搜索', () {
    final policy = QuizSearchPolicy();
    const stem = '机动车通过路口时应当如何操作';
    policy.recordSuccess(
      stem: stem,
      options: const [],
      source: QuizResultSource.localBank,
      questionScore: 62,
      optionScore: 0,
    );

    expect(
      policy.shouldSuppress(stem: stem, options: const ['减速', '鸣笛']),
      isFalse,
    );
  });

  test('高质量本地题库命中锁住同题刷新，但手动刷新可绕过', () {
    final policy = QuizSearchPolicy();
    const stem = '机动车通过路口时应当如何操作';
    const options = ['减速', '鸣笛', '加速', '停车'];
    policy.recordSuccess(
      stem: stem,
      options: options,
      source: QuizResultSource.localBank,
      questionScore: 100,
      optionScore: 100,
    );

    expect(policy.shouldSuppress(stem: stem, options: options), isTrue);
    expect(
      policy.shouldSuppress(stem: stem, options: options, manualRefresh: true),
      isFalse,
    );
  });

  test('高质量结果不能被较低优先级结果覆盖', () {
    final policy = QuizSearchPolicy();
    policy.recordSuccess(
      stem: '题目',
      options: const ['A', 'B'],
      source: QuizResultSource.localBank,
      questionScore: 100,
      optionScore: 100,
    );
    expect(policy.canReplaceWith(QuizResultSource.externalApi), isFalse);
    expect(policy.canReplaceWith(QuizResultSource.localBank), isTrue);
  });

  test('同题干同选项但题图指纹变化时不受上一题命中锁抑制', () {
    final policy = QuizSearchPolicy();
    const stem = '这个标志是何含义？';
    const options = ['堤坝路', '上陡坡', '下陡坡', '连续上坡'];
    policy.recordSuccess(
      stem: stem,
      options: options,
      imageHash: '1111111111111111',
      source: QuizResultSource.localBank,
      questionScore: 100,
      optionScore: 100,
    );

    expect(
      policy.shouldSuppress(
        stem: stem,
        options: options,
        imageHash: '1111111111111111',
      ),
      isTrue,
    );
    expect(
      policy.shouldSuppress(
        stem: stem,
        options: options,
        imageHash: '2222222222222222',
      ),
      isFalse,
    );
  });

  // 回归（2026-09-12 用户报障「第一题一直不出答案，后面题目秒出」）：
  // 试捕/自动捕获在冷启动时会连发两次同题请求（首次读屏 + 重试/OCR 兜底）。
  // 3 秒节流窗把第二次静默吞掉，而第一次可能因题库未加载完而返回空
  // → 悬浮窗永久停在「检索中」。
  // 节流必须放行「同一题目在窗口内再次请求」，只用于拦截完全重复的成功结果。
  test('冷启动连发同题：未产生成功结果前不得因节流丢弃第二次请求', () {
    final policy = QuizSearchPolicy();
    const stem = '驾驶机动车不按规定使用灯光的，一次记3分。';
    const options = ['正确', '错误'];

    // 第一次请求：题库尚未加载完 → 无成功结果
    expect(
      policy.shouldSuppressThrottled(stem: stem, options: options),
      isFalse,
    );
    policy.recordAttempt(stem: stem, options: options);

    // 第二次请求（同一题，窗口内）：首次并未成功，必须放行
    expect(
      policy.shouldSuppressThrottled(stem: stem, options: options),
      isFalse,
    );
  });

  test('已有成功结果时：同题窗口内重复请求仍被节流', () {
    final policy = QuizSearchPolicy();
    const stem = '驾驶机动车不按规定使用灯光的，一次记3分。';
    const options = ['正确', '错误'];
    // 真实调用顺序：先发起请求，再产出成功结果。
    policy.recordAttempt(stem: stem, options: options);
    policy.recordSuccess(
      stem: stem,
      options: options,
      source: QuizResultSource.localBank,
      questionScore: 100,
      optionScore: 100,
    );

    expect(
      policy.shouldSuppressThrottled(stem: stem, options: options),
      isTrue,
    );
  });
}

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
}

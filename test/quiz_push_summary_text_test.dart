import 'package:box/features/quiz_plugin/data/quiz_cloud_push.dart';
import 'package:flutter_test/flutter_test.dart';

/// 推送结果提示必须能自解释。
///
/// 真实故障：用户重推带图题后「后台没有待审核投稿」，
/// 而旧提示只有「提交1·云端已有1」这样的数字，看不出
/// 「已被去重、不会进审核队列」，白白多花一轮排查。
void main() {
  QuizCloudPushResult result({
    int submitted = 0,
    int pending = 0,
    int merged = 0,
    int failed = 0,
    List<String> mergedQuestionIds = const [],
  }) => QuizCloudPushResult(
    serverUrl: 'https://box.example',
    total: submitted + failed,
    submitted: submitted,
    pending: pending,
    merged: merged,
    skippedCloud: 0,
    invalid: 0,
    failed: failed,
    mergedQuestionIds: mergedQuestionIds,
  );

  test('全被去重时要说明不会进审核队列，并给出云端题目 ID', () {
    final text = result(
      submitted: 1,
      merged: 1,
      mergedQuestionIds: ['cloud-q-123'],
    ).summaryText;

    expect(text, contains('云端已有 1'));
    expect(text, contains('不会再进审核队列'));
    expect(
      text,
      contains('cloud-q-123'),
      reason: '没有 ID，用户不知道该去后台编辑哪一条',
    );
  });

  test('拿不到 ID 时不得渲染空括号', () {
    final text = result(submitted: 1, merged: 1).summaryText;
    expect(text, contains('不会再进审核队列'));
    expect(text, isNot(contains('（题目 ID：）')));
  });

  test('正常进入待审核时不加多余解释', () {
    final text = result(submitted: 2, pending: 2).summaryText;
    expect(text, '提交 2 · 待审 2');
  });

  test('一条都没成功时提示去看失败原因', () {
    final text = result(failed: 1).summaryText;
    expect(text, contains('没有任何题进入待审核队列'));
  });

  test('多条被去重时最多列 3 个 ID，避免提示过长', () {
    final text = result(
      submitted: 5,
      merged: 5,
      mergedQuestionIds: ['a', 'b', 'c', 'd', 'e'],
    ).summaryText;
    expect(text, contains('a、b、c'));
    expect(text, isNot(contains('d')));
  });
}

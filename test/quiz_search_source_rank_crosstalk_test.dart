import 'package:flutter_test/flutter_test.dart';
import 'package:box/features/quiz_plugin/domain/quiz_search_policy.dart';

/// 第三轮报障根因（2026-09-12）：
/// 「所有题 20 秒都没出答案，一直检索中，以前 1 秒不到就出了」。
///
/// `_bestSource` 是**跨题持久的单例状态**，从不随切题重置。
/// 一旦某题命中外部队列/OCR 之外的低秩来源…反向：一旦某题命中 localBank(rank 4)，
/// 后续题若返回更低秩的 source，`canReplaceWith` 返回 false，
/// `_runSearch` 在 **更新悬浮窗之前** `return` → 悬浮窗永远停在「检索中」。
void main() {
  test('跨题污染：上一题的来源排名会掐死后续题的结果展示', () {
    final p = QuizSearchPolicy();

    // 第 1 题：本地题库高质量命中 rank=4
    p.recordSuccess(
      stem: '第一题的题干',
      options: const ['A', 'B'],
      source: QuizResultSource.localBank,
      questionScore: 100,
      optionScore: 100,
    );

    // 第 2 题：真实调用点会传当前题指纹 → 与上一题不同 → 必须放行
    final canReplace = p.canReplaceWith(
      QuizResultSource.externalApi,
      stem: '第二题的题干',
    );

    expect(
      canReplace,
      isTrue,
      reason: '切到新题后，上一题的 localBank(rank=4) 不得掐死新题的 '
          'externalApi(rank=2) 结果。canReplaceWith=false 会让 _runSearch 在'
          '「更新悬浮窗之前」return → 悬浮窗永远停在「检索中」，'
          '表现为「所有题 20 秒都不出答案」',
    );
  });

  test('跨题污染：更典型的低秩来源（unknown/OCR）同样被掐死', () {
    final p = QuizSearchPolicy();
    p.recordSuccess(
      stem: '第一题',
      options: const ['A', 'B'],
      source: QuizResultSource.localBank,
      questionScore: 100,
      optionScore: 100,
    );
    // 第 2 题走 OCR 本地题库（rank=3 < 4），带新题指纹
    expect(
      p.canReplaceWith(QuizResultSource.ocrLocalBank, stem: '第二题'),
      isTrue,
      reason: '切题后 OCR 命中也必须能展示；被上一题的 rank=4 挡住则整屏卡「检索中」',
    );
  });

  test('同题内仍须保护：低秩来源不得覆盖高质量命中', () {
    final p = QuizSearchPolicy();
    p.recordSuccess(
      stem: '同一题的题干',
      options: const ['A', 'B'],
      source: QuizResultSource.localBank,
      questionScore: 100,
      optionScore: 100,
    );
    // 同题：仍应被拦（这是原先就有的正确行为，不能被本次修复推翻）
    expect(
      p.canReplaceWith(QuizResultSource.externalApi, stem: '同一题的题干'),
      isFalse,
      reason: '同题内低优先级结果不得覆盖高质量本地题库命中',
    );
  });

  test('存在切题重置 API 时，重置后应立即放行任何来源', () {
    final p = QuizSearchPolicy();
    p.recordSuccess(
      stem: '第一题',
      options: const ['A', 'B'],
      source: QuizResultSource.localBank,
      questionScore: 100,
      optionScore: 100,
    );
    p.resetForNewQuestion();
    expect(p.canReplaceWith(QuizResultSource.externalApi), isTrue);
    expect(p.canReplaceWith(QuizResultSource.unknown), isTrue,
        reason: '切题重置后不得残留上一题的来源排名');
  });
}

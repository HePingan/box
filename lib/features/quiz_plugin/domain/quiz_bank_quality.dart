import 'quiz_bank.dart';

/// 本地题库质量的只读摘要，给自检页和报障文本用。
///
/// 背景（2026-11-22）：用户报「答题助手题目匹配 bug 很多」，实测题库 3616 题里
/// 134 组同题干不同答案、图形题几乎没图 —— 这些是**数据形态**问题，不是匹配算法
/// 能通过调阈值解决的。以前要我手工跑脚本才能看到，现在用户自己就能在自检页看到。
class QuizBankQualitySummary {
  const QuizBankQualitySummary({
    required this.total,
    required this.ambiguousGroups,
    required this.ambiguousItems,
    required this.withImage,
    required this.withRegionHash,
    required this.newRule,
    required this.answerOutOfRange,
  });

  final int total;
  final int ambiguousGroups;
  final int ambiguousItems;
  final int withImage;
  final int withRegionHash;
  final int newRule;
  final int answerOutOfRange;

  static QuizBankQualitySummary summarize(List<QuizBankItem> items) {
    final byStem = <String, List<QuizBankItem>>{};
    var withImage = 0;
    var withRegionHash = 0;
    var newRule = 0;
    var answerOutOfRange = 0;

    for (final item in items) {
      final stem = QuizBankTextNormalizer.cleanForMatch(item.question);
      if (stem.isNotEmpty) {
        (byStem[stem] ??= []).add(item);
      }
      if ((item.imageUrl ?? '').trim().isNotEmpty ||
          (item.imagePerceptualHash ?? '').trim().isNotEmpty) {
        withImage++;
      }
      if ((item.imageRegionHash ?? '').trim().isNotEmpty) withRegionHash++;
      if (item.isNewRule) newRule++;
      final answer = item.correctAnswer.trim();
      if (answer.isNotEmpty &&
          !item.options.any((o) => o.trim() == answer)) {
        answerOutOfRange++;
      }
    }

    var groups = 0;
    var ambiguous = 0;
    for (final group in byStem.values) {
      if (group.length < 2) continue;
      final answers =
          group.map((e) => e.correctAnswer.trim()).toSet();
      if (answers.length > 1) {
        groups++;
        ambiguous += group.length;
      }
    }

    return QuizBankQualitySummary(
      total: items.length,
      ambiguousGroups: groups,
      ambiguousItems: ambiguous,
      withImage: withImage,
      withRegionHash: withRegionHash,
      newRule: newRule,
      answerOutOfRange: answerOutOfRange,
    );
  }

  /// 一行式摘要，直接进「复制结论」。
  String describe() =>
      '题库 $total 题｜同题干异答案 $ambiguousGroups 组/$ambiguousItems 题'
      '｜带题图 $withImage（区域指纹 $withRegionHash）'
      '｜新规标记 $newRule｜答案越界 $answerOutOfRange';
}

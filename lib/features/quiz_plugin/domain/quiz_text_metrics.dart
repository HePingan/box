import 'dart:math';

import 'quiz_bank.dart';

/// 题库文本度量原语的**唯一实现**。
///
/// 2026-11-18 审计 P1-3/P1-4：同一套算法曾经有两份逐字相同的实现
/// （`quiz_answer_aligner._lcs` 与 `quiz_engine._longestCommonSubsequenceLength`），
/// 相似度同算法却**限幅不同**（90 vs 72），`isImageLikeOption` 也是两份。
/// 两份实现的问题不是"多写了几行"，而是改一处漏另一处 —— 这类漂移直接决定
/// 「这道题算不算命中」，错了就是错答案。
///
/// ⚠️ 本文件只收**纯函数**，不改任何阈值语义：
/// - 相似度的字符集合限幅由调用方给（`jaccardCap`），因为两条链路的宽容度
///   是**故意**不同的（对齐器 90、引擎 72），把阈值统一等于改行为。
/// - `stemFingerprint` / dHash 的语义**不在**这里，也不要搬进来。
class QuizTextMetrics {
  QuizTextMetrics._();

  /// 最长公共子序列长度（滚动数组，O(min) 空间）。
  static int lcsLength(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final previous = List<int>.filled(b.length + 1, 0);
    final current = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        current[j] = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1)
            ? previous[j - 1] + 1
            : max(previous[j], current[j - 1]);
      }
      for (var j = 0; j <= b.length; j++) {
        previous[j] = current[j];
        current[j] = 0;
      }
    }
    return previous[b.length];
  }

  /// 0~100 的相似度百分比。
  ///
  /// 取「LCS 双向比例」与「字符集 Jaccard」的较大者；Jaccard 用 [jaccardCap] 限幅，
  /// 因为字符集合重叠会把「机动车/道路/正确/错误」这类通用词误判成高相似。
  ///
  /// [exactShortcut]：完全相等直接 100。对齐器原本有这个短路，引擎没有 ——
  /// 保留差异（引擎那边完全相等时 LCS 也会给 100，结果一致，但短路语义不同）。
  static int similarityPercent(
    String a,
    String b, {
    required int jaccardCap,
    bool exactShortcut = true,
  }) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (exactShortcut && a == b) return 100;
    final lcs = lcsLength(a, b);
    final lcsScore = (lcs * 200 / (a.length + b.length)).round();
    final setA = a.split('').toSet();
    final setB = b.split('').toSet();
    final union = setA.union(setB).length;
    final inter = setA.intersection(setB).length;
    final jaccard = union == 0 ? 0 : (inter * 100 / union).round();
    return max(lcsScore, min(jaccard, jaccardCap));
  }

  /// 「图1 / 图片 / 如图」这类**图形选项**（不是文字选项）。
  ///
  /// 为什么要单独认：图形选项在 OCR/题面里拿不到可比文本，一旦被当成文字选项
  /// 参与打分，题库里同题干的另一道题会以高分误命中。
  static bool isImageLikeOption(String raw) {
    final n = QuizBankTextNormalizer.normalizeOption(raw);
    if (n.isEmpty) return false;
    return RegExp(r'^图\s*\d+$').hasMatch(n) ||
        RegExp(r'^图[一二三四五六七八九十]+$').hasMatch(n) ||
        RegExp(r'^图片\d*$').hasMatch(n) ||
        n == '如图' ||
        n == '见图';
  }

  /// 一组选项里**至少一半是图形选项** ⇒ 认为这组选项是图形选项集。
  static bool isImageLikeOptionSet(List<String> options) {
    final cleaned = options.map((e) => e.trim()).where((e) => e.isNotEmpty);
    if (cleaned.isEmpty) return false;
    final imageCount = cleaned.where(isImageLikeOption).length;
    return imageCount >= max(1, (cleaned.length + 1) ~/ 2);
  }

  /// 剥掉选项字母前缀（`A.` / `Ａ、` / `B)` / `C：`）。
  ///
  /// 审计 P1-3：选项字母前缀的处理原先散在 5 处，且有的只认 A-D、有的认 A-H。
  /// 这里统一按**并集**（A-H + 全角）实现；调用方若需要更窄的口径请自己判，
  /// 但**不要**再复制一份正则。
  static String stripOptionLetterPrefix(String text) {
    return text.replaceFirst(
      RegExp(r'^\s*[A-Ha-hＡ-Ｈ]\s*[.、．:：)）]\s*'),
      '',
    );
  }

  /// 这一行是不是选项行（`A.` / `①` / 判断题的「正确/错误」）。
  static bool isOptionLine(String line) => QuizBankTextNormalizer.isOptionLine(line);
}

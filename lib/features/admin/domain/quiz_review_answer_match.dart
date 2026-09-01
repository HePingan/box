/// 审核界面「哪个选项是正确答案」的判定。
///
/// 旧实现直接 `q.answer == opt` 比字符串，于是：
/// - 答案存成字母（`C`）时，一个选项都高亮不了，审核员得自己数；
/// - 答案原文带首尾空白时同样失配；
/// - 多选答案（`AC`）完全不支持。
///
/// 这里把字母序号、原文、判断题别名统一处理，并额外暴露
/// [isAnswerResolvable]，让审核端能主动指出「答案对不上任何选项」的坏投稿。
///
/// 与 `quiz_plugin/domain/quiz_bank.dart` 里的 `QuizAnswerProjection` 的分工：
/// 后者面向客户端 `QuizBankItem`，只处理**单个**字母答案并投影成选项原文；
/// 本类面向管理端 `QuizBankQuestion`，返回**下标集合**以支持多选高亮。
/// 两者都必须遵守同一条底线：字母越界或答案对不上时不编造答案。
class QuizReviewAnswerMatch {
  const QuizReviewAnswerMatch._();

  static const Map<String, String> _trueFalseAliases = <String, String>{
    '对': '正确',
    '√': '正确',
    'true': '正确',
    '是': '正确',
    '错': '错误',
    '×': '错误',
    'false': '错误',
    '否': '错误',
  };

  /// 返回被判定为正确答案的选项下标（升序、去重）。
  static List<int> correctIndexes({
    required List<String> options,
    required String answer,
  }) {
    final ans = answer.trim();
    if (ans.isEmpty || options.isEmpty) return const <int>[];

    final hits = <int>{};

    // 1) 原文全等（归一化空白后）
    final normAns = _normalize(ans);
    for (var i = 0; i < options.length; i++) {
      if (_normalize(options[i]) == normAns) hits.add(i);
    }

    // 2) 判断题别名
    if (hits.isEmpty) {
      final alias = _trueFalseAliases[normAns.toLowerCase()];
      if (alias != null) {
        for (var i = 0; i < options.length; i++) {
          if (_normalize(options[i]) == alias) hits.add(i);
        }
      }
    }

    // 3) 去掉选项自带的 "A." / "A、" 前缀后再比原文
    if (hits.isEmpty) {
      for (var i = 0; i < options.length; i++) {
        if (_stripLetterPrefix(_normalize(options[i])) == normAns) hits.add(i);
      }
    }

    // 4) 字母序号（含多选 AC / A、C / B,D）
    //    仅当答案里只有字母与常见分隔符时才走这条，避免把
    //    正文里恰好含字母的原文答案误当序号。
    if (hits.isEmpty && _looksLikeLetterKey(ans)) {
      for (final ch in ans.toUpperCase().split('')) {
        final code = ch.codeUnitAt(0);
        if (code < 65 || code > 90) continue;
        final idx = code - 65;
        if (idx >= 0 && idx < options.length) hits.add(idx);
      }
    }

    final out = hits.toList()..sort();
    return List<int>.unmodifiable(out);
  }

  /// 答案能否在选项中定位。
  ///
  /// 没有选项的题型（判断/填空）返回 true —— 它们本来就不靠选项对齐。
  static bool isAnswerResolvable({
    required List<String> options,
    required String answer,
  }) {
    if (options.isEmpty) return true;
    return correctIndexes(options: options, answer: answer).isNotEmpty;
  }

  static String _normalize(String v) =>
      v.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _stripLetterPrefix(String v) {
    final m = RegExp(r'^[A-Za-z]\s*[.、．)）:：]\s*').firstMatch(v);
    return m == null ? v : v.substring(m.end).trim();
  }

  /// 只含字母和分隔符（`AC`、`A、C`、`B,D`、`A B`）才算字母答案。
  static bool _looksLikeLetterKey(String v) {
    final compact = v.replaceAll(RegExp(r'[\s,，、;；/|]'), '');
    if (compact.isEmpty || compact.length > 8) return false;
    return RegExp(r'^[A-Za-z]+$').hasMatch(compact);
  }
}

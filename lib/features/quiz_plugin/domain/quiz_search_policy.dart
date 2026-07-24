import './quiz_bank.dart';

enum QuizResultSource { localBank, ocrLocalBank, externalApi, unknown }

/// 搜题请求的质量门控：防重复检索，也允许半题命中被完整题纠正。
class QuizSearchPolicy {
  String _lockedStem = '';
  String _lockedOptions = '';
  QuizResultSource? _bestSource;

  static String stemFingerprint(String raw) =>
      QuizBankTextNormalizer.stripQuestionPrefix(
        raw,
      ).replaceAll(RegExp(r'\s+'), '').toLowerCase();

  static List<String> normalizedOptions(List<String> options) =>
      options
          .map(QuizBankTextNormalizer.normalizeOption)
          .where((e) => e.isNotEmpty)
          .toList()
        ..sort();

  static String _optionsKey(List<String> options) =>
      normalizedOptions(options).join('|');

  bool shouldSuppress({
    required String stem,
    required List<String> options,
    bool manualRefresh = false,
  }) {
    if (manualRefresh) return false;
    final normalizedStem = stemFingerprint(stem);
    if (normalizedStem.isEmpty || normalizedStem != _lockedStem) return false;
    // 选项补全/变化表示题目质量提升或同题干另一题，允许受控复搜。
    return _lockedOptions == _optionsKey(options);
  }

  void recordSuccess({
    required String stem,
    required List<String> options,
    required QuizResultSource source,
    required int questionScore,
    required int optionScore,
  }) {
    final isReliableLocal =
        source == QuizResultSource.localBank &&
        questionScore >= 95 &&
        (options.isEmpty || optionScore >= 90);
    _bestSource = source;
    if (isReliableLocal) {
      _lockedStem = stemFingerprint(stem);
      _lockedOptions = _optionsKey(options);
    } else {
      _lockedStem = '';
      _lockedOptions = '';
    }
  }

  bool canReplaceWith(QuizResultSource incoming) {
    if (_bestSource == null) return true;
    return _rank(incoming) >= _rank(_bestSource!);
  }

  int _rank(QuizResultSource source) => switch (source) {
    QuizResultSource.localBank => 4,
    QuizResultSource.ocrLocalBank => 3,
    QuizResultSource.externalApi => 2,
    QuizResultSource.unknown => 1,
  };
}

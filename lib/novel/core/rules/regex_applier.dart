/// 正则替换链工具
class RegexApplier {
  const RegexApplier();

  String applyRegexReplacement(String input, String pattern, String replacement) {
    try {
      final reg = RegExp(pattern);
      return input.replaceAllMapped(reg, (match) {
        return replacement.replaceAllMapped(RegExp(r'\$(\d+)'), (m) {
          final index = int.tryParse(m.group(1) ?? '');
          if (index == null) return m.group(0) ?? '';
          return match.group(index) ?? '';
        });
      });
    } catch (_) {
      return input;
    }
  }

  String cleanRawText(String input, {String? replacePattern}) {
    var text = input.replaceAll(RegExp(r'\s+'), ' ');
    if (replacePattern != null && replacePattern.isNotEmpty) {
      final reg = RegExp(replacePattern);
      text = text.replaceAll(reg, '');
    }
    return text.trim();
  }
}

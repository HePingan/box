/// 小说正文文本清洗工具
class TextCleaner {
  TextCleaner._();

  /// 剥离 HTML 标签并归一化空白（适用于所有小说源正文清洗）
  static String stripHtml(String text) {
    var result = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('\u3000', ' ')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '')
        .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    return normalizeWhitespace(result);
  }

  /// 归一化空白字符（折叠空格、归一化换行、去除首尾空白）
  static String cleanRaw(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 归一化换行符和多余空行
  static String normalizeWhitespace(String text) {
    return text
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}

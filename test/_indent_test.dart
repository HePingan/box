import '../lib/novel/core/text_cleaner.dart';

void main() {
  // Simulate typical chapter content
  final raw = '第一章 测试\n'
      '\n'
      '阳光明媚的早晨，小明走在路上。\n'
      '\n'
      '突然，他看到一只小猫。\n'
      '\n'
      '小猫很可爱，小明决定收养它。\n'
      '\n'
      '从此他们过上了幸福的生活。';

  print('=== RAW INPUT ===');
  print(raw);
  print('');

  // Apply normalizeWhitespace
  final normalized = TextCleaner.normalizeWhitespace(raw);
  print('=== AFTER normalizeWhitespace ===');
  print(normalized);
  print('');

  // Replicate _cleanText logic
  final lines = TextCleaner.normalizeWhitespace(raw).split('\n');
  final cleaned = <String>[];
  for (final line in lines) {
    if (line.isNotEmpty) cleaned.add('\u3000\u3000$line');
  }
  if (cleaned.isEmpty && raw.isNotEmpty) {
    cleaned.add('\u3000\u3000$raw');
  }
  final result = cleaned.join('\n');

  print('=== AFTER _cleanText (indent) ===');
  print(result);
  print('');

  // Check hex codes
  print('=== FIRST LINE HEX CODES ===');
  if (result.isNotEmpty) {
    final firstLine = result.split('\n').first;
    print('First line chars:');
    for (final c in firstLine.runes) {
      print('  U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')} = "${String.fromCharCode(c)}"');
    }
  }
}

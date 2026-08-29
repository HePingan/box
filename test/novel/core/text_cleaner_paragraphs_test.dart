import 'package:box/novel/core/text_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：正文分段归一化必须是**全源共享的一份实现**。
///
/// 历史缺陷（Shape 1 规则漂移）：`normalizeParagraphs` 原本是
/// `RuleNovelSource._normalizeParagraphs` 私有方法，只有通用 Rule 源受益。
/// wtzw 源的 `_cleanText` 裸调 `TextCleaner.stripHtml`，而 stripHtml 会把
/// `\u3000` 归一化成普通空格 —— 全角缩进这个唯一的分段信号被消灭，
/// 整章正文压成一行，用户看到「一章就一段」。
void main() {
  group('TextCleaner.normalizeParagraphs', () {
    test('空输入安全', () {
      expect(TextCleaner.normalizeParagraphs(''), '');
      expect(TextCleaner.normalizeParagraphs('   '), '');
    });

    test('已有真换行的正文保留分段', () {
      final out = TextCleaner.normalizeParagraphs('甲段。\n乙段。\n丙段。');
      expect(out.split('\n').where((e) => e.trim().isNotEmpty).length, 3);
    });

    test('HTML <br>/<p> 正文还原为分段', () {
      final out = TextCleaner.normalizeParagraphs(
        '<p>甲段。</p><p>乙段。</p>丙段。<br/>丁段。',
      );
      expect(out.split('\n').where((e) => e.trim().isNotEmpty).length, 4);
    });

    test('双重转义的字面量 \\n 还原为真换行', () {
      final out = TextCleaner.normalizeParagraphs('甲段。\\n乙段。\\r\\n丙段。');
      expect(out.contains('\\n'), isFalse, reason: '字面量应被还原');
      expect(out.split('\n').where((e) => e.trim().isNotEmpty).length, 3);
    });

    test('全角空格缩进的一行正文按缩进还原分段（stripHtml 会吃掉 u3000）', () {
      const flat = '\u3000\u3000甲段内容。\u3000\u3000乙段内容。\u3000\u3000丙段内容。';
      final out = TextCleaner.normalizeParagraphs(flat);
      final paras = out.split('\n').where((e) => e.trim().isNotEmpty).toList();
      expect(paras.length, 3, reason: '缩进检测必须发生在 stripHtml 之前');
    });

    test('无缩进无换行的长正文按句末标点兜底断段', () {
      final flat = '甲段结束了。${'乙段也结束了。' * 30}';
      final out = TextCleaner.normalizeParagraphs(flat);
      expect(out.contains('\n'), isTrue, reason: '长压平正文必须被断段');
    });

    test('兜底断段不拆开 。」 和 ……', () {
      const src = '他说：「走吧。」然后离开了。剩下的人沉默着……夜色渐深。';
      final out = TextCleaner.normalizeParagraphs(src);
      expect(out.contains('。\n」'), isFalse, reason: '不得把 。」 拆开');
      expect(out.contains('…\n…'), isFalse, reason: '不得把 …… 拆开');
    });

    test('短正文无换行不强行断段（如「本章内容为空」）', () {
      const short = '本章内容为空';
      expect(TextCleaner.normalizeParagraphs(short), short);
    });

    test('多余空行折叠，不产生大片空白', () {
      final out = TextCleaner.normalizeParagraphs('甲段。\n\n\n\n\n乙段。');
      expect(out.contains('\n\n\n'), isFalse);
    });
  });
}

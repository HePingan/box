// 文本度量原语收口后的回归（2026-11-18 审计 P1-3/P1-4）。
//
// 为什么值得单独测：`lcs` / `similarity` / `isImageLikeOption` 原本各有两份逐字
// 重复的实现（对齐器与引擎），相似度还**故意**用了不同限幅（90 vs 72）。
// 收口时最容易出的事故是「顺手把阈值统一」，那会直接改变「这题算不算命中」。
// 所以这里把两个限幅值、精确相等短路、图形选项判定都钉死。
import 'package:box/features/quiz_plugin/domain/quiz_text_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lcsLength', () {
    test('完全相等 → 长度等于两者长度', () {
      expect(QuizTextMetrics.lcsLength('abcd', 'abcd'), 4);
    });
    test('空串 → 0', () {
      expect(QuizTextMetrics.lcsLength('', 'abc'), 0);
      expect(QuizTextMetrics.lcsLength('abc', ''), 0);
    });
    test('子序列（非连续）', () {
      expect(QuizTextMetrics.lcsLength('abcde', 'ace'), 3);
    });
    test('无公共字符 → 0', () {
      expect(QuizTextMetrics.lcsLength('abc', 'xyz'), 0);
    });
  });

  group('similarityPercent 的两个限幅必须保持不同', () {
    test('完全相等：对齐器（90 档）走短路 → 100', () {
      expect(
        QuizTextMetrics.similarityPercent('机动车逆向行驶', '机动车逆向行驶',
            jaccardCap: 90),
        100,
      );
    });

    test('字符集高度重叠但顺序不同：Jaccard 被限幅（90 档不超过 90）', () {
      final s = QuizTextMetrics.similarityPercent('abcd', 'dcba', jaccardCap: 90);
      expect(s, lessThanOrEqualTo(90));
    });

    test('同一对文本，72 档不得高于 90 档的结果', () {
      const a = '驾驶机动车在高速公路上倒车的一次记12分';
      const b = '驾驶机动车在高速公路上逆行的一次记12分';
      final wide = QuizTextMetrics.similarityPercent(a, b, jaccardCap: 90);
      final strict = QuizTextMetrics.similarityPercent(a, b, jaccardCap: 72);
      expect(strict, lessThanOrEqualTo(wide),
          reason: '引擎的限幅比对齐器严，收口时不能把两者合并成一个数值');
    });

    test('空串 → 0（两条链路一致）', () {
      expect(QuizTextMetrics.similarityPercent('', 'x', jaccardCap: 90), 0);
      expect(QuizTextMetrics.similarityPercent('x', '', jaccardCap: 72), 0);
    });

    test('exactShortcut=false 时完全相等仍是 100（LCS 本身给满分）', () {
      expect(
        QuizTextMetrics.similarityPercent('正确', '正确',
            jaccardCap: 72, exactShortcut: false),
        100,
      );
    });
  });

  group('图形选项识别', () {
    test('图1 / 图十二 / 图片 / 如图 / 见图 都算图形选项', () {
      for (final raw in ['图1', '图 2', '图十二', '图片', '图片3', '如图', '见图']) {
        expect(QuizTextMetrics.isImageLikeOption(raw), isTrue,
            reason: '$raw 应判为图形选项');
      }
    });

    test('普通文字选项不算', () {
      for (final raw in ['正确', '错误', '减速慢行', 'A. 停车让行']) {
        expect(QuizTextMetrics.isImageLikeOption(raw), isFalse,
            reason: '$raw 不应判为图形选项');
      }
    });

    test('半数以上是图形 ⇒ 整组算图形选项集', () {
      expect(QuizTextMetrics.isImageLikeOptionSet(['图1', '图2', '文字选项']), isTrue);
      expect(QuizTextMetrics.isImageLikeOptionSet(['图1', '文字一', '文字二']), isFalse);
      expect(QuizTextMetrics.isImageLikeOptionSet([]), isFalse);
      // 空串不计入分母
      expect(QuizTextMetrics.isImageLikeOptionSet(['图1', '', ' ']), isTrue);
    });
  });

  group('选项字母前缀', () {
    test('剥半角/全角/各种分隔符', () {
      for (final raw in ['A. 停车让行', 'B、减速慢行', 'C：按喇叭', 'D) 通行', 'Ａ．停车']) {
        expect(
          QuizTextMetrics.stripOptionLetterPrefix(raw).startsWith(RegExp(r'[A-HＡ-Ｈ]')),
          isFalse,
          reason: '$raw 的字母前缀应被剥掉',
        );
      }
    });

    test('没有前缀的文本原样返回（不误伤「机动车」这类中文）', () {
      expect(QuizTextMetrics.stripOptionLetterPrefix('机动车'), '机动车');
    });
  });

  group('isOptionLine（并集口径）', () {
    test('A-H 都算选项行（分隔符用 ASCII 冒号：现有实现不认全角「：」）', () {
      for (final line in ['A. 甲', 'h、乙', 'G: 丙', 'H．丁']) {
        expect(QuizTextMetrics.isOptionLine(line), isTrue, reason: line);
      }
      // 记录当前口径：全角冒号**不**算选项行分隔符。这是既有行为，
      // 收口时只做委托、不顺手改口径（改了会影响 cleanForMatch 的清洗结果）。
      expect(QuizTextMetrics.isOptionLine('G：丙'), isFalse);
    });
    test('圈号与判断题词也算', () {
      expect(QuizTextMetrics.isOptionLine('① 甲'), isTrue);
      expect(QuizTextMetrics.isOptionLine('正确'), isTrue);
      expect(QuizTextMetrics.isOptionLine('错误'), isTrue);
    });
    test('普通题干行不算', () {
      expect(QuizTextMetrics.isOptionLine('驾驶机动车逆向行驶的一次记几分'), isFalse);
    });
  });
}

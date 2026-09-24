// 279 O6（收尾）：Unicode 归一化差异的识别与处置。
//
// 背景：dart:core 没有 NFC/NFD 实现，真做"改写"要引表驱动依赖（单独立项，且改写
// 本身有风险）。这一版做的是"能确定判断"的部分：把预组合字符拆成 NFD 后比对，
// 精确识别"同一个名字的两种归一化形态"，用在两个真会出错的地方——
// 上传冲突判定（避免造出重复文件）与目录诊断日志。

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // NFC（预组合）与 NFD（分解 + 组合记号）的同一串：é
  const nfc = 'caf\u00e9.txt'; // café.txt（é = U+00E9）
  const nfd = 'cafe\u0301.txt'; // cafe + U+0301
  const plain = 'cafe.txt';

  group('归一化变体识别（O6）', () {
    test('NFC 与 NFD 是变体', () {
      expect(isNormalizationVariant(nfc, nfd), isTrue);
      expect(isNormalizationVariant(nfd, nfc), isTrue, reason: '判据对称');
    });

    test('真的不同名字不能误判成变体（否则上传会当同名跳过）', () {
      expect(isNormalizationVariant(plain, nfc), isFalse, reason: 'cafe vs café');
      expect(isNormalizationVariant('resume.txt', 'r\u00e9sum\u00e9.txt'), isFalse);
      expect(isNormalizationVariant('caf\u00e9.txt', 'caf\u00e8.txt'), isFalse,
          reason: 'é vs è 是两个名字，不是两种形态');
      expect(isNormalizationVariant('a.txt', 'b.txt'), isFalse);
    });

    test('自己和自己不算变体（相等就不是"差异"）', () {
      expect(isNormalizationVariant(nfc, nfc), isFalse);
    });

    test('toNfd：预组合字符拆成基字符 + 组合记号', () {
      expect(toNfd(nfc), nfd);
      expect(toNfd(nfd), nfd, reason: '已经是 NFD 的保持不变');
      expect(toNfd(plain), plain);
      expect(toNfd(''), '');
    });

    test('表外字符原样保留（不猜、不改写）', () {
      // 韩文音节、emoji、中文都不在表里
      expect(toNfd('한글.txt'), '한글.txt');
      expect(toNfd('报告（2024）.txt'), '报告（2024）.txt');
      expect(toNfd('🎬movie.mp4'), '🎬movie.mp4');
    });

    test('退化输入不误判（空串）', () {
      expect(isNormalizationVariant('', ''), isFalse);
      expect(isNormalizationVariant('a', ''), isFalse);
      expect(isNormalizationVariant('', 'a'), isFalse);
    });

    test('希腊/西里尔也覆盖（含多字节组合记号）', () {
      // ά（U+03AC，NFC） vs α + U+0301（NFD）
      expect(isNormalizationVariant('\u03ac', '\u03b1\u0301'), isTrue);
      // й（U+0439） vs и + U+0306
      expect(isNormalizationVariant('\u0439', '\u0438\u0306'), isTrue);
    });

    test('归一化表格自身没坏：常见带变音字母都能拆开', () {
      for (final sample in const [
        'àáâãäåāăą',
        'ÀÁÂÃÄÅĀĂĄ',
        'çćĉċč',
        'èéêëēĕėęě',
        'ìíîïĩīĭįǐ',
        'òóôõöōŏőơ',
        'ùúûüũūŭůűųư',
        'ñńņňǹ',
        'żźž',
      ]) {
        for (final ch in sample.split('')) {
          expect(
            toNfd(ch),
            isNot(ch),
            reason: '$ch 应该能拆成基字符 + 组合记号',
          );
        }
      }
    });

    test('normalizationVariantOf：在候选里找到变体', () {
      expect(normalizationVariantOf(nfd, [plain, nfc]), nfc);
      expect(normalizationVariantOf(nfd, [plain]), isNull);
      expect(normalizationVariantOf(nfd, const []), isNull);
      expect(
        normalizationVariantOf(nfc, ['报告.txt', 'movie.mp4']),
        isNull,
        reason: '无关名字不该命中',
      );
    });
  });
}

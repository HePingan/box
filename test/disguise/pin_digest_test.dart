import 'package:box/features/disguise/domain/pin_digest.dart';
import 'package:flutter_test/flutter_test.dart';

/// 口令摘要与定长时间比较。
///
/// 这两件事错了不会立刻报错，只会安静地降低安全性（或者是"口令永远对"），
/// 所以必须有断言守着。
void main() {
  group('盐与摘要', () {
    test('盐是 16 字节 hex', () {
      final salt = randomSaltHex();
      expect(salt.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(salt), isTrue);
    });

    test('每次的盐都不一样', () {
      expect(randomSaltHex() == randomSaltHex(), isFalse);
    });

    test('摘要固定 64 位 hex，同盐同口令结果稳定', () {
      final salt = randomSaltHex();
      final first = hashPin(salt, '123456');
      expect(first.length, 64);
      expect(hashPin(salt, '123456'), first);
    });

    test('换盐或换口令都会换摘要', () {
      final salt = randomSaltHex();
      final digest = hashPin(salt, '123456');
      expect(hashPin(randomSaltHex(), '123456'), isNot(digest));
      expect(hashPin(salt, '123457'), isNot(digest));
    });
  });

  group('定长时间比较', () {
    test('相同摘要判定相等', () {
      final salt = randomSaltHex();
      final digest = hashPin(salt, '123456');
      expect(constantTimeHexEquals(digest, digest), isTrue);
    });

    test('首位不同 / 末位不同都判不等', () {
      final salt = randomSaltHex();
      final digest = hashPin(salt, '123456');
      // 替换字符必须**真的和原位不同**：盐是随机生成的，摘要首位有 1/16 概率
      // 正好是 'f'，写死 'f' 的版本会随机变成"和自我比较"然后失败（实测撞到过）。
      String flip(String hex, int index) {
        final replacement = hex[index] == 'f' ? '0' : 'f';
        return hex.replaceRange(index, index + 1, replacement);
      }

      expect(constantTimeHexEquals(digest, flip(digest, 0)), isFalse);
      expect(constantTimeHexEquals(digest, flip(digest, 63)), isFalse);
      expect(constantTimeHexEquals(digest, flip(digest, 31)), isFalse);
    });

    test('空串 / 非法 hex / 长度不同都判不等', () {
      final salt = randomSaltHex();
      final digest = hashPin(salt, '123456');
      expect(constantTimeHexEquals('', digest), isFalse);
      expect(constantTimeHexEquals('zzzz', digest), isFalse);
      expect(constantTimeHexEquals(digest, '${digest}00'), isFalse);
    });
  });

  group('口令合法性', () {
    test('4–12 位纯数字', () {
      expect(isValidPin('1234'), isTrue);
      expect(isValidPin('123456789012'), isTrue);
      expect(isValidPin('0000'), isTrue);
    });

    test('长度越界与非数字都拒绝', () {
      expect(isValidPin('123'), isFalse);
      expect(isValidPin('1234567890123'), isFalse);
      expect(isValidPin('12a4'), isFalse);
      expect(isValidPin(''), isFalse);
      expect(isValidPin('12 34'), isFalse);
    });
  });

  group('恢复码', () {
    test('生成为 4 组 4 位，共 16 个字符', () {
      final code = randomRecoveryCode();
      expect(code, matches(RegExp(r'^[0-9A-Z]{4}(-[0-9A-Z]{4}){3}$')));
      expect(normalizeRecoveryCode(code).length, kRecoveryLength);
    });

    test('字母表里没有会抄错的 0 O 1 I L', () {
      for (final banned in ['0', 'O', '1', 'I', 'L']) {
        expect(kRecoveryAlphabet.contains(banned), isFalse, reason: banned);
      }
      // 1000 枚里一个都不许漏出来：字母表错了这里立刻就抓到。
      for (var i = 0; i < 1000; i++) {
        final code = randomRecoveryCode();
        expect(RegExp('[0O1IL]').hasMatch(code), isFalse, reason: code);
      }
    });

    test('两次生成不会撞（熵够用）', () {
      final codes = <String>{};
      for (var i = 0; i < 200; i++) {
        codes.add(randomRecoveryCode());
      }
      expect(codes.length, 200);
    });

    test('排版幂等；长度不对就只归一化', () {
      const bare = 'k7qtm2xr9wpd4fzg';
      expect(formatRecoveryCode(bare), 'K7QT-M2XR-9WPD-4FZG');
      expect(formatRecoveryCode('K7QT-M2XR-9WPD-4FZG'), 'K7QT-M2XR-9WPD-4FZG');
      expect(formatRecoveryCode('K7QT'), 'K7QT');
    });

    test('输入归一化吃掉空格/连字符/大小写', () {
      const canonical = 'K7QTM2XR9WPD4FZG';
      for (final variant in [
        'K7QT-M2XR-9WPD-4FZG',
        'k7qt m2xr 9wpd 4fzg',
        '  K7QT\nM2XR\t9WPD-4FZG  ',
        'k7qtm2xr9wpd4fzg',
      ]) {
        expect(normalizeRecoveryCode(variant), canonical, reason: variant);
      }
      expect(normalizeRecoveryCode(''), '');
      expect(normalizeRecoveryCode('---'), '');
    });
  });
}

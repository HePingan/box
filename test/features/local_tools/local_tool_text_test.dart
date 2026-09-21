import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/local_tools/domain/local_tool_text.dart' as t;

/// 批次 2 纯计算逻辑单测：JSON 格式化、正则测试、Base64、哈希、URL 编码、
/// 文本统计、颜文字。
void main() {
  group('JSON 格式化', () {
    test('美化：两空格缩进 + 保留中文不转义', () {
      final out = t.formatJson('{"a":1,"b":[1,2],"中文":"值"}');
      expect(out, contains('\n'));
      expect(out, contains('  "a": 1'));
      // 中文不能被转成 \uXXXX
      expect(out, contains('中文'));
      expect(out, isNot(contains(r'\u4e2d')));
    });

    test('压缩：去掉所有换行与多余空格', () {
      final out = t.minifyJson('{\n  "a": 1,\n  "b": [1, 2]\n}');
      expect(out, '{"a":1,"b":[1,2]}');
    });

    test('非法 JSON 报明确错误，不返回半成品', () {
      expect(() => t.formatJson('{"a":'), throwsA(isA<t.TextToolError>()));
      expect(() => t.minifyJson('not json'), throwsA(isA<t.TextToolError>()));
    });

    test('顶层非对象/数组（裸字符串）也算非法', () {
      expect(() => t.formatJson('123'), throwsA(isA<t.TextToolError>()));
    });

    test('空输入报错而不是返回空', () {
      expect(() => t.formatJson('   '), throwsA(isA<t.TextToolError>()));
    });
  });

  group('正则测试', () {
    test('列出所有匹配及位置', () {
      final r = t.testRegex(r'\d+', 'a12b345c');
      expect(r.matches.length, 2);
      expect(r.matches[0].text, '12');
      expect(r.matches[0].start, 1);
      expect(r.matches[1].text, '345');
    });

    test('捕获组内容', () {
      final r = t.testRegex(r'(\w+)@(\w+)', 'mail: bob@example');
      expect(r.matches.length, 1);
      expect(r.matches[0].groups, ['bob', 'example']);
    });

    test('非法正则报错', () {
      expect(() => t.testRegex('([', 'abc'), throwsA(isA<t.TextToolError>()));
    });

    test('无匹配返回空列表而不是抛错', () {
      final r = t.testRegex(r'zzz', 'abc');
      expect(r.matches, isEmpty);
    });

    test('全局标志默认开启（不会只返回第一个）', () {
      final r = t.testRegex('a', 'aaa');
      expect(r.matches.length, 3);
    });
  });

  group('Base64', () {
    test('编码中文（UTF-8），不是 latin1', () {
      expect(t.base64EncodeText('中文'), '5Lit5paH');
    });

    test('解码回原文', () {
      expect(t.base64DecodeText('5Lit5paH'), '中文');
    });

    test('往返一致（含 emoji）', () {
      const s = 'Hello 世界 🎉';
      expect(t.base64DecodeText(t.base64EncodeText(s)), s);
    });

    test('非法 Base64 报错', () {
      expect(() => t.base64DecodeText('!!!not-base64!!!'),
          throwsA(isA<t.TextToolError>()));
    });

    test('容忍换行与空格的 Base64', () {
      expect(t.base64DecodeText('5Lit\n5paH'), '中文');
    });
  });

  group('哈希', () {
    test('MD5 已知向量', () {
      expect(t.hashText('abc', t.HashAlgo.md5),
          '900150983cd24fb0d6963f7d28e17f72');
    });

    test('SHA-1 已知向量', () {
      expect(t.hashText('abc', t.HashAlgo.sha1),
          'a9993e364706816aba3e25717850c26c9cd0d89d');
    });

    test('SHA-256 已知向量', () {
      expect(t.hashText('abc', t.HashAlgo.sha256),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('中文按 UTF-8 编码后哈希', () {
      expect(t.hashText('中文', t.HashAlgo.md5), 'a7bac2239fcdcb3a067903d8077c4a07');
    });

    test('结果是小写十六进制，长度正确', () {
      expect(t.hashText('x', t.HashAlgo.md5).length, 32);
      expect(t.hashText('x', t.HashAlgo.sha1).length, 40);
      expect(t.hashText('x', t.HashAlgo.sha256).length, 64);
    });
  });

  group('URL 编码', () {
    test('编码保留 RFC 3986 的 unreserved 字符', () {
      expect(t.urlEncodeText('a-b_c.d~e'), 'a-b_c.d~e');
    });

    test('空格编成 %20 而不是 +', () {
      expect(t.urlEncodeText('a b'), 'a%20b');
    });

    test('中文按 UTF-8 百分号编码', () {
      expect(t.urlEncodeText('中'), '%E4%B8%AD');
    });

    test('解码还原', () {
      expect(t.urlDecodeText('%E4%B8%AD%20a'), '中 a');
    });

    test('往返一致', () {
      const s = 'https://x.com/搜索?q=中文&n=1';
      expect(t.urlDecodeText(t.urlEncodeText(s)), s);
    });

    test('非法百分号序列报错', () {
      expect(() => t.urlDecodeText('%E4%B8'),
          throwsA(isA<t.TextToolError>()));
    });
  });

  group('文本统计', () {
    test('字符数 / 去空格字符数 / 行数 / 词数', () {
      // 'hello world' = 11，'\n' = 1，'你好' = 2 → 共 14 个字符；
      // 去掉空格与换行后 12 个。
      final s = t.textStats('hello world\n你好');
      expect(s.chars, 14);
      expect(s.charsNoSpace, 12);
      expect(s.lines, 2);
      expect(s.words, 3); // hello / world / 你好（中文按整块算一段）
    });

    test('空文本全零，不崩', () {
      final s = t.textStats('');
      expect(s.chars, 0);
      expect(s.lines, 0);
    });
  });

  group('颜文字', () {
    test('表非空且都是非空字符串', () {
      expect(t.kaomojiList, isNotEmpty);
      for (final k in t.kaomojiList) {
        expect(k.trim(), isNotEmpty);
      }
    });

    test('按 seed 取可复现', () {
      expect(t.pickKaomoji(0), t.pickKaomoji(0));
      expect(t.pickKaomoji(0), t.kaomojiList[0]);
    });

    test('越界 seed 自动取模，不抛异常', () {
      expect(() => t.pickKaomoji(9999), returnsNormally);
    });
  });
}

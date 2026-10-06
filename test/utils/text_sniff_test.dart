// 文本/二进制的内容判据（不看文件名）用例。
//
// 这条判据原先只活在 server_ops 的编辑器里，于是"点开一个文件该走文本还是
// 交给别的应用"用的是后缀白名单 —— 白名单没命中的一律当二进制，真机上
// `.dev.vars`（113 B 纯文本）就被弹了「这是二进制文件」。抽出来之后两端共用。
import 'dart:convert';
import 'dart:typed_data';

import 'package:box/utils/text_sniff.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('textSniffLooksBinary', () {
    test('含 NUL 判为二进制', () {
      expect(textSniffLooksBinary(Uint8List.fromList([104, 105, 0, 33])), isTrue);
    });

    test('普通脚本不是二进制', () {
      expect(textSniffLooksBinary(bytesOf('#!/bin/sh\necho hi\n')), isFalse);
    });

    test('只看开头 8KB：NUL 在很后面就不算（也不该为此把整个文件读一遍）', () {
      final big = Uint8List(kTextSniffBytes + 16);
      for (var i = 0; i < big.length; i++) {
        big[i] = 0x41;
      }
      big[kTextSniffBytes + 4] = 0;
      expect(textSniffLooksBinary(big), isFalse);
    });
  });

  group('textSniffIsValidUtf8', () {
    test('中文 UTF-8 合法', () {
      expect(textSniffIsValidUtf8(bytesOf('你好，世界\n')), isTrue);
    });

    test('GBK 字节序列不合法（存回去会写坏文件）', () {
      expect(
        textSniffIsValidUtf8(Uint8List.fromList([0xC4, 0xE3, 0xBA, 0xC3])),
        isFalse,
      );
    });
  });

  group('textSniffNameLooksNonText', () {
    test('图片/视频/音频/压缩包/可执行文件都算"按名字就不可能是文本"', () {
      for (final name in [
        'a.png',
        'b.JPG',
        'c.mp4',
        'd.mp3',
        'e.zip',
        'f.tar.gz',
        'g.pdf',
        'h.apk',
        'i.font.ttf',
      ]) {
        expect(
          textSniffNameLooksNonText(name),
          isTrue,
          reason: '$name 不必读开头就能否定',
        );
      }
    });

    test('纯文本名（含真机翻车的那批）不落进"快速否定"', () {
      for (final name in [
        '.dev.vars',
        '.env',
        '.env.local',
        'Dockerfile',
        'Makefile',
        'README',
        'nginx.conf.bak',
        'id_rsa.pub',
        'notes.txt',
      ]) {
        expect(
          textSniffNameLooksNonText(name),
          isFalse,
          reason: '$name 是文本，必须留给按内容判断那一跳',
        );
      }
    });

    test('没有后缀的名字不算"快速否定"（Dockerfile 就是这一类）', () {
      expect(textSniffNameLooksNonText('Dockerfile'), isFalse);
      expect(textSniffNameLooksNonText('无扩展名'), isFalse);
    });

    test('只有点开头、没有后缀（.gitignore）也不算快速否定', () {
      expect(textSniffNameLooksNonText('.gitignore'), isFalse);
    });
  });

  group('textSniffSaysText', () {
    test('纯文本为真', () {
      expect(textSniffSaysText(bytesOf('API_KEY=abc\n')), isTrue);
    });

    test('二进制与空内容为假', () {
      expect(textSniffSaysText(Uint8List.fromList([1, 0, 2])), isFalse);
      expect(textSniffSaysText(Uint8List(0)), isFalse);
    });

    test('非 UTF-8 为假', () {
      expect(textSniffSaysText(Uint8List.fromList([0xC4, 0xE3])), isFalse);
    });
  });
}

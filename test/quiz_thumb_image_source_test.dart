import 'dart:convert';

import 'package:box/features/admin/domain/quiz_thumb_image_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// 列表缩略图的取源判定。
///
/// 后台列表里 image 字段来源混杂：服务端 URL、内嵌 data URL、
/// 还有被截断/缺 base64 段的脏数据。旧实现直接 `image.split(',')[1]` 再 base64Decode，
/// 脏数据会在 build 里抛异常，把整个列表项糊成红块。
/// 这里把判定收成纯函数，脏数据一律降级成占位图。
void main() {
  group('data URL 内嵌图', () {
    test('合法 data URL 解出字节', () {
      final b64 = base64Encode(const [1, 2, 3, 4]);
      final source = QuizThumbImageSource.parse('data:image/png;base64,$b64');
      expect(source.kind, QuizThumbKind.bytes);
      expect(source.bytes, const [1, 2, 3, 4]);
    });

    test('大小写与空白差异不影响识别', () {
      final b64 = base64Encode(const [9, 9]);
      final source = QuizThumbImageSource.parse(
        '  DATA:image/jpeg;base64,$b64  ',
      );
      expect(source.kind, QuizThumbKind.bytes);
      expect(source.bytes, const [9, 9]);
    });

    test('data URL 少了逗号后半段时降级占位，不抛异常', () {
      final source = QuizThumbImageSource.parse('data:image/png;base64');
      expect(source.kind, QuizThumbKind.placeholder);
    });

    test('base64 段是空串时降级占位', () {
      final source = QuizThumbImageSource.parse('data:image/png;base64,');
      expect(source.kind, QuizThumbKind.placeholder);
    });

    test('base64 段被截断成非法字符时降级占位，不抛异常', () {
      final source = QuizThumbImageSource.parse(
        'data:image/png;base64,!!!not-base64!!!',
      );
      expect(source.kind, QuizThumbKind.placeholder);
    });
  });

  group('网络图', () {
    test('http/https 走网络加载', () {
      expect(
        QuizThumbImageSource.parse('https://cdn.example.com/a.png').kind,
        QuizThumbKind.network,
      );
      expect(
        QuizThumbImageSource.parse('http://cdn.example.com/a.png').kind,
        QuizThumbKind.network,
      );
    });

    test('网络图保留去空白后的原始地址', () {
      final source = QuizThumbImageSource.parse(
        '  https://cdn.example.com/a.png ',
      );
      expect(source.url, 'https://cdn.example.com/a.png');
    });
  });

  group('空与脏值', () {
    test('空串和纯空白都是占位', () {
      expect(QuizThumbImageSource.parse('').kind, QuizThumbKind.placeholder);
      expect(QuizThumbImageSource.parse('   ').kind, QuizThumbKind.placeholder);
    });

    test('既不是 data 也不是 http 的裸字符串降级占位，不当成 URL 请求', () {
      expect(
        QuizThumbImageSource.parse('uploads/xx.png').kind,
        QuizThumbKind.placeholder,
      );
    });
  });

  test('相对路径用 base 解析成完整 URL', () {
    expect(
      QuizThumbImageSource.parse('/uploads/q.png', base: 'https://cdn.example').url,
      'https://cdn.example/uploads/q.png',
    );
    // 相对路径但 base 为空 → 占位
    expect(
      QuizThumbImageSource.parse('/uploads/q.png', base: '').kind,
      QuizThumbKind.placeholder,
    );
  });
}

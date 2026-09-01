import 'dart:convert';
import 'dart:io';

import 'package:box/features/quiz_plugin/data/quiz_submission_image_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('quiz_img_payload');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // 最小合法 PNG（1x1 透明像素）
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGMAAQAABQAB'
    'oIJXOQAAAABJRU5ErkJggg==',
  );

  test('本地图片路径应被内联成 data URL 后再提交（否则审核端只收到无用路径）', () async {
    final f = File('${tmp.path}/q.png')..writeAsBytesSync(pngBytes);

    final payload = await QuizSubmissionImagePayload.inline(f.path);

    expect(payload, isNotNull);
    expect(payload!.startsWith('data:image/png;base64,'), isTrue);
    final comma = payload.indexOf(',');
    expect(base64Decode(payload.substring(comma + 1)), pngBytes);
  });

  test('jpg 走 image/jpeg MIME', () async {
    final f = File('${tmp.path}/q.jpg')..writeAsBytesSync(pngBytes);
    final payload = await QuizSubmissionImagePayload.inline(f.path);
    expect(payload, isNotNull);
    expect(payload!.startsWith('data:image/jpeg;base64,'), isTrue);
  });

  test('file:// URI 也能内联', () async {
    final f = File('${tmp.path}/q.png')..writeAsBytesSync(pngBytes);
    final payload = await QuizSubmissionImagePayload.inline(f.uri.toString());
    expect(payload, isNotNull);
    expect(payload!.startsWith('data:image/png;base64,'), isTrue);
  });

  test('已是 data URL 时原样返回，不重复编码', () async {
    const already = 'data:image/png;base64,AAAA';
    expect(await QuizSubmissionImagePayload.inline(already), already);
  });

  test('已是网络 URL 时返回 null（服务端已有像素，无需内联）', () async {
    expect(
      await QuizSubmissionImagePayload.inline('https://cdn.test/a.png'),
      isNull,
    );
    expect(
      await QuizSubmissionImagePayload.inline('/api/quiz/images/a.png'),
      isNull,
    );
  });

  test('文件不存在时返回 null 而不抛异常', () async {
    expect(
      await QuizSubmissionImagePayload.inline('${tmp.path}/missing.png'),
      isNull,
    );
  });

  test('空值返回 null', () async {
    expect(await QuizSubmissionImagePayload.inline(null), isNull);
    expect(await QuizSubmissionImagePayload.inline('   '), isNull);
  });

  test('超过体积上限的图片拒绝内联，避免请求体过大提交失败', () async {
    final big = File('${tmp.path}/big.png')
      ..writeAsBytesSync(List<int>.filled(
        QuizSubmissionImagePayload.maxInlineBytes + 1,
        0x41,
      ));
    expect(await QuizSubmissionImagePayload.inline(big.path), isNull);
  });

  test('恰好等于上限的图片仍可内联（边界值）', () async {
    final edge = File('${tmp.path}/edge.png')
      ..writeAsBytesSync(List<int>.filled(
        QuizSubmissionImagePayload.maxInlineBytes,
        0x41,
      ));
    expect(await QuizSubmissionImagePayload.inline(edge.path), isNotNull);
  });

  test('buildSubmissionJson 用内联结果覆盖 image 字段', () async {
    final f = File('${tmp.path}/q.png')..writeAsBytesSync(pngBytes);
    final json = await QuizSubmissionImagePayload.buildSubmissionJson(
      <String, dynamic>{'question': 'Q', 'image': f.path},
    );
    expect(json['image'].toString().startsWith('data:image/png;base64,'), isTrue);
    expect(json['question'], 'Q');
  });

  test('buildSubmissionJson 内联失败时移除 image，不提交无用的本地路径', () async {
    final json = await QuizSubmissionImagePayload.buildSubmissionJson(
      <String, dynamic>{
        'question': 'Q',
        'image': '/data/user/0/com.example.box/gone.png',
      },
    );
    expect(json.containsKey('image'), isFalse);
    expect(json['question'], 'Q');
  });
}

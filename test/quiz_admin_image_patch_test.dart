import 'dart:convert';

import 'package:box/features/admin/data/quiz_bank_admin_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// 后台「补图/换图」必须只发图片字段。
///
/// 真实故障：补图时连 `question` + `options` 一起 PATCH 回去，
/// 服务端查重逻辑拿这份题干和完整选项去比库，命中的正是这道题自己，
/// 于是报「题干与完整选项已存在，不能合并覆盖」——补图被自己挡住。
///
/// 只发要改的字段（`image`），查重就无从触发。
class _CapturingClient extends http.BaseClient {
  _CapturingClient(this.captured);

  final List<Map<String, dynamic>> captured;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request && request.body.isNotEmpty) {
      final decoded = jsonDecode(request.body);
      if (decoded is Map) {
        captured.add(Map<String, dynamic>.from(decoded));
      }
    }
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          jsonEncode({
            'question': {
              'id': 'q1',
              'question': '这个标志什么含义？',
              'options': ['甲', '乙'],
              'answer': '甲',
              'image': 'https://cdn.example/new.png',
            },
          }),
        ),
      ),
      200,
      request: request,
    );
  }
}

void main() {
  test('补图只发 image 字段，不回传题干与选项', () async {
    final captured = <Map<String, dynamic>>[];
    final client = QuizBankAdminClient(httpClient: _CapturingClient(captured));

    await client.updateQuestionImage(
      serverUrl: 'https://box.example',
      token: 't',
      id: 'q1',
      imageUrl: 'https://cdn.example/new.png',
    );

    expect(captured, hasLength(1));
    final body = captured.single;
    expect(body['image'], 'https://cdn.example/new.png');
    expect(
      body.containsKey('question'),
      isFalse,
      reason: '回传题干会让服务端查重命中这道题自己，补图被拒',
    );
    expect(
      body.containsKey('options'),
      isFalse,
      reason: '回传完整选项是「不能合并覆盖」报错的直接原因',
    );
    expect(body.keys, ['image']);
  });

  test('清空图片时显式发空串，而不是省略字段', () async {
    final captured = <Map<String, dynamic>>[];
    final client = QuizBankAdminClient(httpClient: _CapturingClient(captured));

    await client.updateQuestionImage(
      serverUrl: 'https://box.example',
      token: 't',
      id: 'q1',
      imageUrl: '',
    );

    expect(captured.single.containsKey('image'), isTrue);
    expect(captured.single['image'], '');
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:box/features/admin/data/quiz_bank_admin_client.dart';
import 'package:box/features/admin/presentation/widgets/quiz_bank_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 回归：管理面板「补图」的**所有**入口都必须把客户端算出的 dHash 一并送出。
///
/// 缺陷背景（实测）：
/// - 服务端**从不**计算 dHash（`fromRequest` 只从请求体读 `imagePerceptualHash`
///   / `imageRegionHash`），`set_image` 分支只 `copyWith(image:)`。
/// - App 管理面板四个补图入口过去**只发 `image`**，于是入库的题「有图无指纹」，
///   引擎 `_bestImageScore` 因 `imageRegionHash` 为空直接 `return -1` →
///   同题干多候选依然二选一 → 用户看到的仍是「请人工确认」。
/// - ⇒ 只传图 = 白传。必须同时带 `imagePerceptualHash` 与 `imageRegionHash`。
///
/// 契约（见 references/manual-question-image-region-hash.md）：
/// 手动上传的题图**只含题目插图**，故其 dHash 可**同时**作为
/// `imagePerceptualHash` 与 `imageRegionHash`（两者同值）。
void main() {
  // 一个最小合法 PNG（1x1 纯色），供 computeDHash 解码。
  const pngB64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
      'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

  Uint8List tinyPng() => base64Decode(pngB64);

  String dataUrl() => 'data:image/png;base64,${base64Encode(tinyPng())}';

  group('补图必须带 dHash 指纹', () {
    test('bulkUpdateQuestions 接受并发送 imagePerceptualHash/imageRegionHash',
        () async {
      Map<String, dynamic>? sent;
      final client = QuizBankAdminClient(
        httpClient: MockClient((req) async {
          sent = jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
          return http.Response.bytes(
            utf8.encode(jsonEncode({'updated': 1})),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await client.bulkUpdateQuestions(
        serverUrl: 'http://x',
        token: 't',
        action: 'set_image',
        ids: ['q1'],
        image: '/api/quiz/images/a.jpg',
        imagePerceptualHash: 'abcdef0123456789',
        imageRegionHash: 'abcdef0123456789',
      );

      expect(sent, isNotNull, reason: '请求体必须真的发出去');
      expect(sent!['image'], '/api/quiz/images/a.jpg');
      // 红灯：当前 bulkUpdateQuestions 没有这两个参数 → 这里会是 null
      expect(sent!['imagePerceptualHash'], 'abcdef0123456789');
      expect(sent!['imageRegionHash'], 'abcdef0123456789');
    });

    test('completeIncomplete 接受并发送 hash', () async {
      Map<String, dynamic>? sent;
      final client = QuizBankAdminClient(
        httpClient: MockClient((req) async {
          sent = jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
          return http.Response.bytes(
            utf8.encode(jsonEncode({'ok': true})),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await client.completeIncomplete(
        serverUrl: 'http://x',
        token: 't',
        id: 'q1',
        correctAnswer: 'A',
        image: '/api/quiz/images/a.jpg',
        imagePerceptualHash: 'abcdef0123456789',
        imageRegionHash: 'abcdef0123456789',
      );

      expect(sent!['imagePerceptualHash'], 'abcdef0123456789');
      expect(sent!['imageRegionHash'], 'abcdef0123456789');
    });

    test('provider 层 bulkUpdateQuestions/completeIncomplete 透传 hash', () async {
      Map<String, dynamic>? sent;
      final client = QuizBankAdminClient(
        httpClient: MockClient((req) async {
          sent = jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
          return http.Response.bytes(
            utf8.encode(jsonEncode({'updated': 1})),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final provider = QuizBankResourceProvider(client: client);

      await provider.bulkUpdateQuestions(
        'http://x',
        't',
        action: 'set_image',
        ids: ['q1'],
        image: '/api/quiz/images/a.jpg',
        imagePerceptualHash: 'deadbeefdeadbeef',
        imageRegionHash: 'deadbeefdeadbeef',
      );

      expect(sent!['imagePerceptualHash'], 'deadbeefdeadbeef');
      expect(sent!['imageRegionHash'], 'deadbeefdeadbeef');
    });

    test('computeImageHashes 从 data URL 算出 16 位小写 hex，两值同源', () async {
      final hashes = await QuizBankImageHash.computeFromDataUrl(dataUrl());
      expect(hashes, isNotNull);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(hashes!.regionHash), isTrue,
          reason: '必须匹配引擎校验 ^[0-9a-f]{16}\$');
      expect(hashes.perceptualHash, hashes.regionHash,
          reason: '纯题图：整图 dHash 同时作为 regionHash');
    });
  });
}

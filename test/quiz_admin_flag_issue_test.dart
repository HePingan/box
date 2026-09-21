import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:box/features/admin/data/quiz_bank_admin_client.dart';

/// 「标记为问题题」回归测试（RED -> GREEN）。
///
/// 背景：题库里有「题干相同、答案由图决定」的冲突题，无图无法判断对错。
/// 用户拍板：不猜答案，改为把这类题**标记**出来，且**后端要显示**。
///
/// 后端已有「残缺（incomplete）」队列 + `/admin/quiz/incomplete` 端点，
/// 但那只收导入时校验失败的题，**已发布的题标不进去**。
/// 故本档复用既有残缺管道：把已发布题 PATCH 成 `status: incomplete`。
///
/// 契约（服务端 merge 语义）：
///   1) PATCH 只发 `status` + `issueReason`，**不能回传 question/options**
///      —— 带了会被服务端查重逻辑拦下（「题干与完整选项已存在」）。
///   2) issueReason 用来记录「为什么标它」，后端列表与残缺队列据此显示。
///      注意字段名是 `issueReason` 而非 `reason`：服务端的 `reason` 是
///      残缺记录自有字段，PATCH 题目的 handler 只认 `issueReason`。
void main() {
  group('标记为问题题（route into incomplete queue）', () {
    test('PATCH 只发 status/issueReason，不回传题干与选项（避免触发查重）', () async {
      var captured = <String, dynamic>{};
      var capturedPath = '';

      final client = QuizBankAdminClient(
        httpClient: MockClient((request) async {
          capturedPath = request.url.path;
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'question': {
                'questionId': 'q_conflict01',
                'question': '请判断图中左侧的机动车有几种违法行为？',
                'type': 'single_choice',
                'options': ['一种违法行为', '两种违法行为', '三种违法行为', '四种违法行为'],
                'correctAnswer': '三种违法行为',
                'status': 'incomplete',
                'issueReason': '需按图确认答案',
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final updated = await client.flagQuestionAsIssue(
        serverUrl: 'https://example.test',
        token: 'tok',
        id: 'q_conflict01',
        reason: '需按图确认答案',
      );

      // 命中正确的端点
      expect(capturedPath, '/admin/quiz/questions/q_conflict01');
      // 核心契约：只发这两个字段
      expect(captured.keys.toSet(), {'status', 'issueReason'});
      expect(captured['status'], 'incomplete');
      expect(captured['issueReason'], '需按图确认答案');
      // 绝不能把题干/选项塞回去，否则被服务端查重拦下
      expect(captured.containsKey('question'), isFalse);
      expect(captured.containsKey('options'), isFalse);
      // 返回体的 status 应为 incomplete，供 UI 刷新标记
      expect(updated.status, 'incomplete');
    });

    test('取消标记：PATCH 回 published', () async {
      var captured = <String, dynamic>{};
      final client = QuizBankAdminClient(
        httpClient: MockClient((request) async {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'question': {
                'questionId': 'q_conflict01',
                'question': 'x',
                'status': 'published',
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final updated = await client.flagQuestionAsIssue(
        serverUrl: 'https://example.test',
        token: 'tok',
        id: 'q_conflict01',
        reason: '',
        flagged: false,
      );

      expect(captured['status'], 'published');
      expect(updated.status, 'published');
    });

    test('默认 reason 为空时不发送 issueReason 字段', () async {
      var captured = <String, dynamic>{};
      final client = QuizBankAdminClient(
        httpClient: MockClient((request) async {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'question': {'questionId': 'q_x', 'question': 'x', 'status': 'incomplete'},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      await client.flagQuestionAsIssue(
        serverUrl: 'https://example.test',
        token: 'tok',
        id: 'q_x',
      );

      expect(captured.containsKey('issueReason'), isFalse);
      expect(captured['status'], 'incomplete');
    });
  });
}

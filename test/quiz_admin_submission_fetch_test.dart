import 'dart:convert';

import 'package:box/features/admin/data/quiz_bank_admin_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// 审核端拉取待审核投稿的健壮性。
///
/// 真实故障：用户重推后「后台管理还是没有出现待审核投稿」。
/// 除了提交端的问题，拉取端也有两处会导致「查无此条」：
///   1. `/admin/quiz/submissions/pending` 只认 status=pending，
///      服务端若写 pending_review 就漏掉。
///   2. 列表可能嵌在 `data.submissions` 里，旧代码只看顶层。
void main() {
  Map<String, dynamic> sub(String id, String status) => {
    'id': id,
    'status': status,
    'question': {
      'question': '题干$id',
      'options': ['甲', '乙'],
      'correctAnswer': '甲',
    },
  };

  test('/pending 返回结构不可识别时，回退到通用列表并筛出待审核', () async {
    final paths = <String>[];
    final client = QuizBankAdminClient(
      httpClient: _Stub(paths, (path) {
        if (path.endsWith('/pending')) {
          // 该路径不被服务端支持：没有任何可识别的列表字段
          return {'message': 'unsupported'};
        }
        return {
          'submissions': [
            sub('s1', 'pending_review'),
            sub('s2', 'approved'),
            sub('s3', 'pending'),
          ],
        };
      }),
    );

    final list = await client.fetchPendingSubmissions(
      serverUrl: 'https://box.example',
      token: 't',
    );

    expect(paths.first, '/admin/quiz/submissions/pending');
    expect(paths.length, 2, reason: '空结果必须触发一次兜底查询');
    expect(
      list.map((e) => e.id),
      ['s1', 's3'],
      reason: 'pending_review 与 pending 都算待审核，approved 要滤掉',
    );
  });

  test('列表嵌在 data.submissions 里也能解析', () async {
    final paths = <String>[];
    final client = QuizBankAdminClient(
      httpClient: _Stub(paths, (_) {
        return {
          'data': {
            'submissions': [sub('n1', 'pending')],
          },
        };
      }),
    );

    final list = await client.fetchPendingSubmissions(
      serverUrl: 'https://box.example',
      token: 't',
    );
    expect(list.single.id, 'n1');
    expect(paths.length, 1, reason: '首次就拿到数据，不该再兜底');
  });

  test('/pending 合法返回空列表时不得多打一次请求', () async {
    final paths = <String>[];
    final client = QuizBankAdminClient(
      httpClient: _Stub(paths, (_) => {'submissions': <dynamic>[]}),
    );
    final list = await client.fetchPendingSubmissions(
      serverUrl: 'https://box.example',
      token: 't',
    );
    expect(list, isEmpty);
    expect(
      paths,
      ['/admin/quiz/submissions/pending'],
      reason: '空列表是合法答案，不该为此再查一次通用列表',
    );
  });

  test('/pending 有数据时不做多余请求', () async {
    final paths = <String>[];
    final client = QuizBankAdminClient(
      httpClient: _Stub(paths, (_) {
        return {
          'submissions': [sub('p1', 'pending')],
        };
      }),
    );
    final list = await client.fetchPendingSubmissions(
      serverUrl: 'https://box.example',
      token: 't',
    );
    expect(list.single.id, 'p1');
    expect(paths.length, 1);
  });
}

class _Stub extends http.BaseClient {
  _Stub(this.paths, this.build);

  final List<String> paths;
  final Map<String, dynamic> Function(String path) build;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    paths.add(request.url.path);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(build(request.url.path)))),
      200,
      request: request,
    );
  }
}

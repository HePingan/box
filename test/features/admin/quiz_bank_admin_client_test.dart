import 'dart:convert';

import 'package:box/features/admin/data/quiz_bank_admin_client.dart';
import 'package:box/features/admin/domain/admin_resource.dart';
import 'package:box/features/admin/domain/quiz_bank_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('quiz question parses API fields and keeps a serializable payload', () {
    final question = QuizBankQuestion.fromJson({
      'id': 'q-1',
      'question': '2 + 2 = ?',
      'options': ['3', '4'],
      'answer': 'B',
      'status': 'published',
      'tags': ['math'],
    });

    expect(question.id, 'q-1');
    expect(question.options, ['3', '4']);
    expect(question.toJson()['answer'], 'B');
    expect(question.statusLabel, '已发布');
  });

  test(
    'quiz client sends authenticated CRUD requests to questions endpoint',
    () async {
      final requests = <http.Request>[];
      final client = QuizBankAdminClient(
        httpClient: _RecordingClient(requests),
      );

      await client.fetchQuestions(
        serverUrl: 'https://box.example/api',
        token: 'token',
        search: 'math',
      );
      await client.createQuestion(
        serverUrl: 'https://box.example/api',
        token: 'token',
        data: {'question': 'new question'},
      );
      await client.updateQuestion(
        serverUrl: 'https://box.example/api',
        token: 'token',
        id: 'q/1',
        data: {'status': 'published'},
      );
      await client.deleteQuestion(
        serverUrl: 'https://box.example/api',
        token: 'token',
        id: 'q/1',
      );

      expect(requests.map((request) => request.method), [
        'GET',
        'POST',
        'PATCH',
        'DELETE',
      ]);
      expect(requests.first.url.path, '/admin/quiz/questions');
      expect(requests.first.url.queryParameters['search'], 'math');
      expect(requests[1].headers['authorization'], 'Bearer token');
      expect(requests[2].url.path, '/admin/quiz/questions/q%2F1');
      expect(jsonDecode(requests[1].body), {'question': 'new question'});
    },
  );

  test('submission image accepts nested question image fields', () {
    final parsed = QuizBankSubmission.fromJson({
      'id': 'sub-image',
      'status': 'pending_review',
      'question': {
        'question': '带图题',
        'options': ['A', 'B'],
        'imageUrl': 'https://cdn.example/q.png',
      },
    });

    expect(parsed.isPending, isTrue);
    expect(parsed.question.image, 'https://cdn.example/q.png');
  });

  test('submission review endpoints and parse submitterUserId', () async {
    final parsed = QuizBankSubmission.fromJson({
      'id': 'sub-1',
      'status': 'pending',
      'submitterUserId': 'u-9',
      'submittedAt': '2026-07-19T12:00:00Z',
      'question': {
        'id': 'tmp',
        'question': '停车让行？',
        'options': ['A', 'B'],
        'correctAnswer': 'B',
        'status': 'pending',
      },
    });
    expect(parsed.submitter, 'u-9');
    expect(parsed.statusLabel, '待审核');
    expect(parsed.question.answer, 'B');

    final requests = <http.Request>[];
    final client = QuizBankAdminClient(httpClient: _RecordingClient(requests));
    await client.fetchPendingSubmissions(
      serverUrl: 'https://box.example',
      token: 'admin',
    );
    await client.reviewSubmission(
      serverUrl: 'https://box.example',
      token: 'admin',
      id: 'sub/1',
      action: 'approve',
    );
    await client.reviewSubmission(
      serverUrl: 'https://box.example',
      token: 'admin',
      id: 'sub/1',
      action: 'reject',
      reviewNote: '答案不清',
    );

    expect(requests[0].url.path, '/admin/quiz/submissions/pending');
    expect(requests[1].url.path, '/admin/quiz/submissions/sub%2F1/approve');
    expect(requests[2].url.path, '/admin/quiz/submissions/sub%2F1/reject');
    expect(jsonDecode(requests[2].body), {'reviewNote': '答案不清'});
  });

  test(
    'quiz resource type follows video source and provider identifies it',
    () {
      expect(
        AdminResourceType.quizBank.order,
        greaterThan(AdminResourceType.videoSource.order),
      );
    },
  );
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.requests);

  final List<http.Request> requests;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final copied = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request is http.Request) copied.bodyBytes = request.bodyBytes;
    requests.add(copied);
    final body = request.method == 'GET'
        ? (request.url.path.contains('submissions')
              ? '{"submissions":[]}'
              : '{"questions":[]}')
        : request.url.path.contains('submissions')
        ? '{"id":"sub-1","status":"pending","question":{"question":"q","options":["A","B"],"correctAnswer":"A"}}'
        : '{}';
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

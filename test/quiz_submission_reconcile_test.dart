import 'dart:convert';

import 'package:box/features/account/data/account_store.dart';
import 'package:box/features/account/domain/account_models.dart';
import 'package:box/features/quiz_plugin/data/quiz_cloud_push.dart';
import 'package:box/features/quiz_plugin/data/quiz_cloud_sync.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.pages);

  final List<Object> pages;
  final List<http.BaseRequest> requests = [];
  int _index = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final page = pages[_index.clamp(0, pages.length - 1)];
    _index++;
    final response = _json(page);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fetchMySubmissions sends auth header and parses review outcome',
    () async {
      final client = _RecordingClient([
        {
          'questions': [
            {
              'id': 'qs_a',
              'status': 'approved',
              'reviewNote': '已通过',
              'linkedQuestionId': 'q_1',
              'reviewedAt': '2026-08-15T10:00:00.000',
              'question': {'question': '题干A'},
            },
            {
              'id': 'qs_b',
              'status': 'merged',
              'reviewNote': '正式题库已存在相同题目',
              'question': {'question': '题干B'},
            },
          ],
          'hasMore': false,
        },
      ]);

      final service = QuizCloudSyncService(httpClient: client);
      final result = await service.fetchMySubmissions(
        serverUrl: 'https://box.example',
        token: 'tok-1',
      );

      expect(result, hasLength(2));
      expect(result.first.id, 'qs_a');
      expect(result.first.status, 'approved');
      expect(result.first.linkedQuestionId, 'q_1');
      expect(result.last.status, 'merged');

      final request = client.requests.single;
      expect(request.headers['Authorization'], 'Bearer tok-1');
      expect(request.url.path, '/api/me/quiz/questions');
    },
  );

  test(
    'fetchMySubmissions follows pagination until hasMore is false',
    () async {
      final client = _RecordingClient([
        {
          'questions': [
            {
              'id': 'qs_1',
              'status': 'approved',
              'question': {'question': '第一页'},
            },
          ],
          'hasMore': true,
        },
        {
          'questions': [
            {
              'id': 'qs_2',
              'status': 'rejected',
              'reviewNote': '答案有误',
              'question': {'question': '第二页'},
            },
          ],
          'hasMore': false,
        },
      ]);

      final service = QuizCloudSyncService(httpClient: client);
      final result = await service.fetchMySubmissions(
        serverUrl: 'https://box.example',
        token: 'tok-1',
      );

      expect(result.map((e) => e.id), ['qs_1', 'qs_2']);
      expect(client.requests, hasLength(2));
      expect(client.requests.last.url.queryParameters['offset'], '1');
    },
  );

  test('reconcileStatuses maps remote outcome onto local sync status', () {
    final decisions = QuizSubmissionReconciler.decide(
      locals: const [
        // 审核通过 → 已上云
        QuizBankItem(
          id: 'local-approved',
          question: '题干A',
          type: QuizQuestionType.singleChoice,
          options: ['A', 'B'],
          correctAnswer: 'A',
          syncStatus: QuizSyncStatus.pendingReview,
          remoteSubmissionId: 'qs_a',
        ),
        // 重复合并 → 云端已有
        QuizBankItem(
          id: 'local-merged',
          question: '题干B',
          type: QuizQuestionType.singleChoice,
          options: ['A', 'B'],
          correctAnswer: 'A',
          syncStatus: QuizSyncStatus.pendingReview,
          remoteSubmissionId: 'qs_b',
        ),
        // 被驳回 → 已拒绝（保留审核备注）
        QuizBankItem(
          id: 'local-rejected',
          question: '题干C',
          type: QuizQuestionType.singleChoice,
          options: ['A', 'B'],
          correctAnswer: 'A',
          syncStatus: QuizSyncStatus.pendingReview,
          remoteSubmissionId: 'qs_c',
        ),
        // 仍在排队 → 保持审核中，不产生写操作
        QuizBankItem(
          id: 'local-pending',
          question: '题干D',
          type: QuizQuestionType.singleChoice,
          options: ['A', 'B'],
          correctAnswer: 'A',
          syncStatus: QuizSyncStatus.pendingReview,
          remoteSubmissionId: 'qs_d',
        ),
        // 云端镜像题不参与对账
        QuizBankItem(
          id: 'cloud-item',
          question: '云端题',
          type: QuizQuestionType.singleChoice,
          options: ['A', 'B'],
          correctAnswer: 'A',
          origin: 'cloud',
          syncStatus: QuizSyncStatus.published,
          remoteSubmissionId: 'qs_a',
        ),
      ],
      remotes: const [
        QuizCloudSubmission(id: 'qs_a', status: 'approved', reviewNote: '已通过'),
        QuizCloudSubmission(id: 'qs_b', status: 'merged', reviewNote: '云端已存在'),
        QuizCloudSubmission(id: 'qs_c', status: 'rejected', reviewNote: '答案有误'),
        QuizCloudSubmission(id: 'qs_d', status: 'pending'),
      ],
    );

    final byId = {for (final d in decisions) d.localId: d};
    expect(byId['local-approved']!.syncStatus, QuizSyncStatus.published);
    expect(byId['local-merged']!.syncStatus, QuizSyncStatus.merged);
    expect(byId['local-rejected']!.syncStatus, QuizSyncStatus.rejected);
    expect(byId['local-rejected']!.reviewNote, '答案有误');
    // 未变化的与云端镜像不产生写操作
    expect(byId.containsKey('local-pending'), isFalse);
    expect(byId.containsKey('cloud-item'), isFalse);
  });

  test('reconcileStatuses falls back to identity match when id is missing', () {
    final decisions = QuizSubmissionReconciler.decide(
      locals: const [
        QuizBankItem(
          id: 'local-no-remote-id',
          question: '历史投稿题',
          type: QuizQuestionType.singleChoice,
          options: ['正确', '错误'],
          correctAnswer: '正确',
          syncStatus: QuizSyncStatus.pendingReview,
        ),
      ],
      remotes: const [
        QuizCloudSubmission(
          id: 'qs_legacy',
          status: 'approved',
          question: '历史投稿题',
          options: ['正确', '错误'],
        ),
      ],
    );

    expect(decisions, hasLength(1));
    expect(decisions.single.localId, 'local-no-remote-id');
    expect(decisions.single.syncStatus, QuizSyncStatus.published);
    expect(decisions.single.remoteSubmissionId, 'qs_legacy');
  });

  test('reconcile coordinator requires login', () async {
    SharedPreferences.setMockInitialValues({});
    final store = BoxAccountStore();
    final service = QuizCloudSyncService(httpClient: _RecordingClient([{}]));

    await expectLater(
      QuizSubmissionReconciler(
        syncService: service,
        accountStore: store,
      ).reconcile(),
      throwsA(isA<QuizCloudSyncException>()),
    );

    await store.saveSession(
      const BoxAccountSession(
        serverUrl: 'https://box.example',
        token: 'tok-1',
        user: BoxAccountUser(
          id: 'u1',
          username: 'tester',
          role: 'user',
          status: 'normal',
        ),
      ),
    );
  });
}

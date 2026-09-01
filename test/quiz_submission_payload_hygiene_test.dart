import 'dart:convert';

import 'package:box/features/quiz_plugin/data/quiz_cloud_sync.dart';
import 'package:box/features/quiz_plugin/domain/quiz_bank.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 投稿请求体卫生。
///
/// 真实故障：用户重新推送后「后台管理没有出现待审核投稿」。
/// 根因是 `QuizBankItem.toJson()` 是**本地存储用**的序列化，
/// 它会把本地同步状态一起发给服务端：
///   - `syncStatus: pending_review`（重推时本地已是审核中）
///   - `origin` / `id` / `remoteSubmissionId` / `lastSubmitAt`
/// 服务端若信任这些字段，就会认为「这条已经在审核中/已有归属」，
/// 于是不再新建待审核记录 —— 客户端却收到 200，显示推送成功。
///
/// 投稿只应描述**题目内容**，状态归属由服务端自己决定。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// 本地状态字段：一律不得出现在投稿体里。
  const forbidden = <String>[
    'syncStatus',
    'origin',
    'remoteSubmissionId',
    'lastSubmitAt',
    'lastSubmitError',
    'id',
  ];

  Future<Map<String, dynamic>> capture(QuizBankItem item) async {
    final requests = <http.Request>[];
    final service = QuizCloudSyncService(httpClient: _Capture(requests));
    await service.submit(
      serverUrl: 'https://box.example',
      token: 't',
      item: item,
      category: 'drive_car',
    );
    return jsonDecode(requests.single.body) as Map<String, dynamic>;
  }

  test('重推审核中的题：投稿体不得带 syncStatus=pending_review', () async {
    final body = await capture(
      const QuizBankItem(
        id: 'local-42',
        question: '这个标志什么含义？',
        type: QuizQuestionType.singleChoice,
        options: ['禁止通行', '允许通行'],
        correctAnswer: '禁止通行',
        // 用户第二次推送时，本地状态正是审核中
        syncStatus: QuizSyncStatus.pendingReview,
        remoteSubmissionId: 'sub-old-1',
      ),
    );

    for (final key in forbidden) {
      expect(
        body.containsKey(key),
        isFalse,
        reason: '投稿体不得携带本地字段 `$key`（值=${body[key]}），'
            '否则服务端可能据此判定「已在审核中」而不新建待审核记录',
      );
    }
  });

  test('投稿体必须完整保留题目内容字段', () async {
    final body = await capture(
      const QuizBankItem(
        id: 'local-43',
        question: '题干',
        type: QuizQuestionType.singleChoice,
        options: ['甲', '乙'],
        correctAnswer: '甲',
        analysis: '解析文本',
        imageSha256: 'abc123',
        imagePerceptualHash: 'def456',
      ),
    );

    expect(body['question'], '题干');
    expect(body['options'], ['甲', '乙']);
    expect(body['correctAnswer'], '甲');
    expect(body['analysis'], '解析文本');
    expect(body['type'], 'single_choice');
    expect(body['category'], 'drive_car');
    // 去重指纹要留着，服务端靠它判同题
    expect(body['imageSha256'], 'abc123');
    expect(body['imagePerceptualHash'], 'def456');
  });

  test('判断题类型正常传递', () async {
    final body = await capture(
      const QuizBankItem(
        id: 'local-44',
        question: '判断题',
        type: QuizQuestionType.trueFalse,
        options: ['正确', '错误'],
        correctAnswer: '正确',
        syncStatus: QuizSyncStatus.rejected,
      ),
    );
    expect(body['type'], 'true_false');
    expect(body.containsKey('syncStatus'), isFalse);
  });
}

class _Capture extends http.BaseClient {
  _Capture(this.requests);

  final List<http.Request> requests;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) requests.add(request);
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(jsonEncode({'id': 'sub-new', 'status': 'pending'})),
      ),
      200,
      request: request,
    );
  }
}

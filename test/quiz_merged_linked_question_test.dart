import 'package:box/features/quiz_plugin/data/quiz_cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// 投稿被去重判成 `merged` 时，服务端会回传 `linkedQuestionId`
/// —— 指向云端那道已存在的题。
///
/// 真实场景：用户给本地题换了图重推，服务端按题干指纹判定同题，
/// 返回 merged。此时云端那道题**可能仍然缺图**，而用户完全看不到
/// 该去改哪一条。这个 ID 是唯一的线索，必须解析出来并展示。
void main() {
  test('merged 响应里的 linkedQuestionId 必须被解析出来', () {
    final parsed = QuizCloudSubmission.fromJson({
      'id': 'sub-9',
      'status': 'merged',
      'linkedQuestionId': 'cloud-q-123',
      'question': {
        'question': '这个标志什么含义？',
        'options': ['禁止通行', '允许通行'],
      },
    });

    expect(parsed.status, 'merged');
    expect(
      parsed.linkedQuestionId,
      'cloud-q-123',
      reason: '没有这个 ID，用户无从知道该去后台改哪一道题',
    );
  });

  test('linkedQuestionId 缺失或空白时归一为 null', () {
    expect(
      QuizCloudSubmission.fromJson({
        'id': 's',
        'status': 'pending',
      }).linkedQuestionId,
      isNull,
    );
    expect(
      QuizCloudSubmission.fromJson({
        'id': 's',
        'status': 'merged',
        'linkedQuestionId': '   ',
      }).linkedQuestionId,
      isNull,
      reason: '空白 ID 等于没有，不能让 UI 显示一个空链接',
    );
  });

  test('merged 时应能从响应拿到云端题干用于人工核对', () {
    final parsed = QuizCloudSubmission.fromJson({
      'id': 'sub-10',
      'status': 'merged',
      'linkedQuestionId': 'cloud-q-9',
      'question': {'question': '云端已有的题干', 'options': ['甲', '乙']},
    });
    expect(parsed.question, '云端已有的题干');
    expect(parsed.options, ['甲', '乙']);
  });
}
